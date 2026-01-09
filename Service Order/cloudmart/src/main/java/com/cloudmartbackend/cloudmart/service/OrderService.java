package com.cloudmartbackend.cloudmart.service;



import com.cloudmartbackend.cloudmart.domain.entity.Order;
import com.cloudmartbackend.cloudmart.domain.entity.OrderItem;
import com.cloudmartbackend.cloudmart.domain.entity.Product;
import com.cloudmartbackend.cloudmart.domain.entity.User;
import com.cloudmartbackend.cloudmart.dto.request.CreateOrderRequest;
import com.cloudmartbackend.cloudmart.dto.request.OrderItemRequest;
import com.cloudmartbackend.cloudmart.dto.response.OrderResponse;
import com.cloudmartbackend.cloudmart.exception.BadRequestException;
import com.cloudmartbackend.cloudmart.exception.ResourceNotFoundException;
import com.cloudmartbackend.cloudmart.exception.UnauthorizedException;
import com.cloudmartbackend.cloudmart.repository.OrderRepository;
import com.cloudmartbackend.cloudmart.repository.ProductRepository;
import com.cloudmartbackend.cloudmart.security.SecurityUtils;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
@Slf4j
public class OrderService {

    private final OrderRepository orderRepository;
    private final ProductRepository productRepository;
    private final SqsService sqsService;
    private final CartService cartService;
    private final SecurityUtils securityUtils;

    @Transactional
    public OrderResponse createOrder(CreateOrderRequest request) {
        User user = securityUtils.getCurrentUser();

        if (request.getItems() == null || request.getItems().isEmpty()) {
            throw new BadRequestException("Order must contain at least one item");
        }

        Order order = Order.builder()
                .orderNumber(generateOrderNumber())
                .user(user)
                .items(new ArrayList<>())
                .shippingAddress(request.getShippingAddress())
                .paymentMethod(request.getPaymentMethod())
                .notes(request.getNotes())
                .status(Order.OrderStatus.PENDING)
                .shippingCost(BigDecimal.ZERO)
                .discount(BigDecimal.ZERO)
                .createdAt(LocalDateTime.now()) // <--- ¡AGREGAR AQUÍ!
                .build();

        // Process order items
        for (OrderItemRequest itemRequest : request.getItems()) {
            Product product = productRepository.findById(itemRequest.getProductId())
                    .orElseThrow(() -> new ResourceNotFoundException("Product not found: " + itemRequest.getProductId()));

            if (product.getStatus() != Product.ProductStatus.ACTIVE) {
                throw new BadRequestException("Product is not available: " + product.getName());
            }

            if (product.getStock() < itemRequest.getQuantity()) {
                throw new BadRequestException("Insufficient stock for product: " + product.getName());
            }

            // Decrease stock
            product.decreaseStock(itemRequest.getQuantity());
            productRepository.save(product);


            OrderItem orderItem = OrderItem.builder()
                    .product(product)
                    .quantity(itemRequest.getQuantity())
                    .unitPrice(product.getPrice())
                    .createdAt(LocalDateTime.now()) // <--- ¡AGREGAR AQUÍ TAMBIÉN!
                    .build();

            order.addItem(orderItem);
        }

        // Calculate totals
        order.calculateTotals();

        Order savedOrder = orderRepository.save(order);

        // Send order to SQS for async processing
        sqsService.sendOrderMessage(savedOrder);

        // Clear user's cart
        try {
            cartService.clearCart();
        } catch (Exception e) {
            log.warn("Failed to clear cart after order creation", e);
        }

        log.info("Order created: {}", savedOrder.getOrderNumber());

        return OrderResponse.fromEntity(savedOrder);
    }

    @Transactional(readOnly = true)
    public OrderResponse getOrderById(Long id) {
        Order order = orderRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Order not found with id: " + id));

        User currentUser = securityUtils.getCurrentUser();

        // User can only see their own orders, admin can see all
        if (!order.getUser().getId().equals(currentUser.getId())
                && currentUser.getRole() != User.UserRole.ADMIN) {
            throw new UnauthorizedException("You don't have permission to view this order");
        }

        return OrderResponse.fromEntity(order);
    }

    @Transactional(readOnly = true)
    public OrderResponse getOrderByNumber(String orderNumber) {
        Order order = orderRepository.findByOrderNumber(orderNumber)
                .orElseThrow(() -> new ResourceNotFoundException("Order not found: " + orderNumber));

        User currentUser = securityUtils.getCurrentUser();

        if (!order.getUser().getId().equals(currentUser.getId())
                && currentUser.getRole() != User.UserRole.ADMIN) {
            throw new UnauthorizedException("You don't have permission to view this order");
        }

        return OrderResponse.fromEntity(order);
    }

    @Transactional(readOnly = true)
    public Page<OrderResponse> getMyOrders(Pageable pageable) {
        User user = securityUtils.getCurrentUser();
        return orderRepository.findByUser(user, pageable)
                .map(OrderResponse::fromEntity);
    }

    @Transactional(readOnly = true)
    public Page<OrderResponse> getAllOrders(Pageable pageable) {
        User currentUser = securityUtils.getCurrentUser();

        if (currentUser.getRole() != User.UserRole.ADMIN) {
            throw new UnauthorizedException("Only admins can view all orders");
        }

        return orderRepository.findAll(pageable)
                .map(OrderResponse::fromEntity);
    }

    @Transactional(readOnly = true)
    public Page<OrderResponse> getOrdersByStatus(Order.OrderStatus status, Pageable pageable) {
        return orderRepository.findByStatus(status, pageable)
                .map(OrderResponse::fromEntity);
    }

    @Transactional
    public OrderResponse updateOrderStatus(Long id, Order.OrderStatus newStatus) {
        User currentUser = securityUtils.getCurrentUser();

        if (currentUser.getRole() != User.UserRole.ADMIN) {
            throw new UnauthorizedException("Only admins can update order status");
        }

        Order order = orderRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Order not found with id: " + id));

        Order.OrderStatus oldStatus = order.getStatus();
        order.setStatus(newStatus);

        Order savedOrder = orderRepository.save(order);

        log.info("Order {} status updated from {} to {}", order.getOrderNumber(), oldStatus, newStatus);

        return OrderResponse.fromEntity(savedOrder);
    }

    @Transactional
    public void cancelOrder(Long id) {
        Order order = orderRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Order not found with id: " + id));

        User currentUser = securityUtils.getCurrentUser();

        if (!order.getUser().getId().equals(currentUser.getId())
                && currentUser.getRole() != User.UserRole.ADMIN) {
            throw new UnauthorizedException("You don't have permission to cancel this order");
        }

        if (order.getStatus() != Order.OrderStatus.PENDING
                && order.getStatus() != Order.OrderStatus.CONFIRMED) {
            throw new BadRequestException("Order cannot be cancelled in current status: " + order.getStatus());
        }

        // Restore stock
        for (OrderItem item : order.getItems()) {
            Product product = item.getProduct();
            product.increaseStock(item.getQuantity());
            productRepository.save(product);
        }

        order.setStatus(Order.OrderStatus.CANCELLED);
        orderRepository.save(order);

        log.info("Order cancelled: {}", order.getOrderNumber());
    }

    private String generateOrderNumber() {
        return "ORD-" + LocalDateTime.now().getYear() + "-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase();
    }
}
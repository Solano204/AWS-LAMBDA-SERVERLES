package com.cloudmartbackend.cloudmart.service;

import com.cloudmartbackend.cloudmart.domain.entity.Cart;
import com.cloudmartbackend.cloudmart.domain.entity.CartItem;
import com.cloudmartbackend.cloudmart.domain.entity.Product;
import com.cloudmartbackend.cloudmart.dto.request.AddToCartRequest;
import com.cloudmartbackend.cloudmart.dto.response.CartResponse;
import com.cloudmartbackend.cloudmart.exception.BadRequestException;
import com.cloudmartbackend.cloudmart.exception.ResourceNotFoundException;
import com.cloudmartbackend.cloudmart.repository.ProductRepository;
import com.cloudmartbackend.cloudmart.security.SecurityUtils;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbTable;
import software.amazon.awssdk.enhanced.dynamodb.Key;

import java.time.Instant;
import java.util.ArrayList;

@Service
@RequiredArgsConstructor
@Slf4j
public class CartService {

    private final DynamoDbTable<Cart> cartTable;
    private final ProductRepository productRepository;
    private final SecurityUtils securityUtils;

    public CartResponse getCart() {
        String userId = String.valueOf(securityUtils.getCurrentUserId());
        Cart cart = cartTable.getItem(Key.builder().partitionValue(userId).build());

        if (cart == null) {
            cart = Cart.builder()
                    .userId(userId)
                    .items(new ArrayList<>())
                    .updatedAt(Instant.now())
                    .build();
        }

        return CartResponse.fromEntity(cart);
    }

    public CartResponse addToCart(AddToCartRequest request) {
        String userId = String.valueOf(securityUtils.getCurrentUserId());

        Product product = productRepository.findById(request.getProductId())
                .orElseThrow(() -> new ResourceNotFoundException("Product not found"));

        if (product.getStatus() != Product.ProductStatus.ACTIVE) {
            throw new BadRequestException("Product is not available");
        }

        if (product.getStock() < request.getQuantity()) {
            throw new BadRequestException("Insufficient stock");
        }

        Cart cart = cartTable.getItem(Key.builder().partitionValue(userId).build());

        if (cart == null) {
            cart = Cart.builder()
                    .userId(userId)
                    .items(new ArrayList<>())
                    .updatedAt(Instant.now())
                    .build();
        }

        CartItem cartItem = CartItem.builder()
                .productId(product.getId())
                .productName(product.getName())
                .price(product.getPrice())
                .quantity(request.getQuantity())
                .imageUrl(product.getImageUrl())
                .availableStock(product.getStock())
                .build();

        cartItem.calculateSubtotal();
        cart.addItem(cartItem);

        cartTable.putItem(cart);

        log.info("Item added to cart for user: {}", userId);

        return CartResponse.fromEntity(cart);
    }

    public CartResponse updateCartItemQuantity(Long productId, int quantity) {
        if (quantity <= 0) {
            throw new BadRequestException("Quantity must be greater than 0");
        }

        String userId = String.valueOf(securityUtils.getCurrentUserId());
        Cart cart = cartTable.getItem(Key.builder().partitionValue(userId).build());

        if (cart == null) {
            throw new ResourceNotFoundException("Cart is empty");
        }

        Product product = productRepository.findById(productId)
                .orElseThrow(() -> new ResourceNotFoundException("Product not found"));

        if (product.getStock() < quantity) {
            throw new BadRequestException("Insufficient stock");
        }

        boolean found = false;
        for (CartItem item : cart.getItems()) {
            if (item.getProductId().equals(productId)) {
                item.setQuantity(quantity);
                item.setAvailableStock(product.getStock());
                item.calculateSubtotal();
                found = true;
                break;
            }
        }

        if (!found) {
            throw new ResourceNotFoundException("Product not found in cart");
        }

        cart.setUpdatedAt(Instant.now());
        cartTable.putItem(cart);

        log.info("Cart item updated for user: {}", userId);

        return CartResponse.fromEntity(cart);
    }

    public CartResponse removeFromCart(Long productId) {
        String userId = String.valueOf(securityUtils.getCurrentUserId());
        Cart cart = cartTable.getItem(Key.builder().partitionValue(userId).build());

        if (cart == null) {
            throw new ResourceNotFoundException("Cart is empty");
        }

        cart.removeItem(productId);
        cartTable.putItem(cart);

        log.info("Item removed from cart for user: {}", userId);

        return CartResponse.fromEntity(cart);
    }

    public void clearCart() {
        String userId = String.valueOf(securityUtils.getCurrentUserId());
        Cart cart = cartTable.getItem(Key.builder().partitionValue(userId).build());

        if (cart != null) {
            cart.clear();
            cartTable.putItem(cart);
            log.info("Cart cleared for user: {}", userId);
        }
    }

    public void syncCartWithInventory() {
        String userId = String.valueOf(securityUtils.getCurrentUserId());
        Cart cart = cartTable.getItem(Key.builder().partitionValue(userId).build());

        if (cart == null || cart.getItems().isEmpty()) {
            return;
        }

        boolean updated = false;

        for (CartItem item : cart.getItems()) {
            Product product = productRepository.findById(item.getProductId()).orElse(null);

            if (product == null || product.getStatus() != Product.ProductStatus.ACTIVE) {
                cart.removeItem(item.getProductId());
                updated = true;
                continue;
            }

            if (item.getQuantity() > product.getStock()) {
                item.setQuantity(product.getStock());
                item.calculateSubtotal();
                updated = true;
            }

            item.setAvailableStock(product.getStock());
            item.setPrice(product.getPrice());
        }

        if (updated) {
            cart.setUpdatedAt(Instant.now());
            cartTable.putItem(cart);
            log.info("Cart synced with inventory for user: {}", userId);
        }
    }
}
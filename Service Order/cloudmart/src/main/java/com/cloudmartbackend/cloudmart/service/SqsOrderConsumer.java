package com.cloudmartbackend.cloudmart.worker;

import com.cloudmartbackend.cloudmart.domain.entity.Order;
import com.cloudmartbackend.cloudmart.repository.OrderRepository;
import com.cloudmartbackend.cloudmart.service.SnsService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.*;

import java.util.List;

@Component
@RequiredArgsConstructor
@Slf4j
public class SqsOrderConsumer {

    private final SqsClient sqsClient;
    private final OrderRepository orderRepository;
    private final SnsService snsService;
    private final ObjectMapper objectMapper;

    @Value("${aws.sqs.order-queue-url}")
    private String orderQueueUrl;

    @Value("${aws.sqs.consumer.enabled:true}")
    private boolean consumerEnabled;

    @Value("${aws.sqs.consumer.max-messages:5}")
    private int maxMessages;

    /**
     * Poll SQS queue every 10 seconds for new order messages
     */
    @Scheduled(fixedDelay = 10000, initialDelay = 5000)
    public void consumeOrderMessages() {
        if (!consumerEnabled || orderQueueUrl == null || orderQueueUrl.isEmpty()) {
            return;
        }

        try {
            ReceiveMessageRequest receiveRequest = ReceiveMessageRequest.builder()
                    .queueUrl(orderQueueUrl)
                    .maxNumberOfMessages(maxMessages)
                    .waitTimeSeconds(10) // Long polling
                    .visibilityTimeout(30) // 30 seconds to process
                    .build();

            ReceiveMessageResponse response = sqsClient.receiveMessage(receiveRequest);
            List<Message> messages = response.messages();

            if (messages.isEmpty()) {
                log.debug("No messages in queue");
                return;
            }

            log.info("Received {} messages from SQS", messages.size());

            for (Message message : messages) {
                try {
                    processOrderMessage(message);
                    deleteMessage(message);
                } catch (Exception e) {
                    log.error("Error processing message: {}", message.messageId(), e);
                    // Message will become visible again after visibility timeout
                }
            }

        } catch (Exception e) {
            log.error("Error consuming messages from SQS", e);
        }
    }

    private void processOrderMessage(Message message) {
        try {
            String messageBody = message.body();
            log.debug("Raw message body: {}", messageBody);

            JsonNode rootNode = objectMapper.readTree(messageBody);

            // Check if this is an SNS notification wrapper
            boolean isSnsNotification = rootNode.has("Type") &&
                    "Notification".equals(rootNode.get("Type").asText());

            JsonNode orderData;

            if (isSnsNotification) {
                log.debug("Detected SNS notification wrapper, extracting inner message");

                // This is an SNS notification - skip it or handle differently
                String innerMessage = rootNode.get("Message").asText();
                String subject = rootNode.has("Subject") ? rootNode.get("Subject").asText() : "N/A";

                log.info("📧 SNS Notification received:");
                log.info("   Subject: {}", subject);
                log.info("   Message: {}", innerMessage.substring(0, Math.min(100, innerMessage.length())) + "...");

                // This is a notification FROM SNS, not an order to process
                // We should skip it
                log.info("⏭️  Skipping SNS notification (not an order message)");
                return;

            } else {
                // Direct SQS message with order data
                orderData = rootNode;
            }

            // Extract order information
            if (!orderData.has("orderId")) {
                log.warn("Message does not contain orderId field, skipping");
                return;
            }

            Long orderId = orderData.get("orderId").asLong();
            String orderNumber = orderData.get("orderNumber").asText();

            log.info("🔄 Processing order: {} (ID: {})", orderNumber, orderId);

            // Step 1: Find order in database
            Order order = orderRepository.findById(orderId)
                    .orElseThrow(() -> new RuntimeException("Order not found: " + orderId));

            // Step 2: Simulate payment processing
            boolean paymentSuccess = processPayment(order);

            if (!paymentSuccess) {
                log.error("❌ Payment failed for order: {}", orderNumber);
                updateOrderStatus(order, Order.OrderStatus.CANCELLED);
                return;
            }

            // Step 3: Update order status to CONFIRMED
            Order.OrderStatus oldStatus = order.getStatus();
            updateOrderStatus(order, Order.OrderStatus.CONFIRMED);

            // Step 4: Send confirmation via SNS
            snsService.publishOrderConfirmation(order);

            log.info("✅ Order processed successfully: {}", orderNumber);

        } catch (Exception e) {
            log.error("Failed to process order message", e);
            throw new RuntimeException("Failed to process order message", e);
        }
    }

    /**
     * Simulate payment processing with external API
     * In real implementation, this would call Stripe, PayPal, etc.
     */
    private boolean processPayment(Order order) {
        log.info("💳 Processing payment for order: {} (Total: ${})",
                order.getOrderNumber(), order.getTotal());

        try {
            // Simulate API call delay
            Thread.sleep(2000);

            // Simulate 95% success rate
            boolean success = Math.random() < 0.95;

            if (success) {
                log.info("✅ Payment successful for order: {}", order.getOrderNumber());
            } else {
                log.error("❌ Payment failed for order: {}", order.getOrderNumber());
            }

            return success;

        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return false;
        }
    }

    private void updateOrderStatus(Order order, Order.OrderStatus newStatus) {
        Order.OrderStatus oldStatus = order.getStatus();
        order.setStatus(newStatus);
        orderRepository.save(order);

        log.info("📝 Order {} status updated: {} -> {}",
                order.getOrderNumber(), oldStatus, newStatus);

        // Notify status change via SNS
        if (newStatus != Order.OrderStatus.PENDING) {
            snsService.publishOrderStatusUpdate(order, oldStatus.name());
        }
    }

    private void deleteMessage(Message message) {
        try {
            DeleteMessageRequest deleteRequest = DeleteMessageRequest.builder()
                    .queueUrl(orderQueueUrl)
                    .receiptHandle(message.receiptHandle())
                    .build();

            sqsClient.deleteMessage(deleteRequest);
            log.debug("Message deleted from queue: {}", message.messageId());

        } catch (Exception e) {
            log.error("Failed to delete message from queue", e);
        }
    }
}
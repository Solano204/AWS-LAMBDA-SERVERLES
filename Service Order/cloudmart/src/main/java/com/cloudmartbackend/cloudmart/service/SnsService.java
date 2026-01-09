package com.cloudmartbackend.cloudmart.service;

import com.cloudmartbackend.cloudmart.domain.entity.Order;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.sns.SnsClient;
import software.amazon.awssdk.services.sns.model.PublishRequest;

@Service
@RequiredArgsConstructor
@Slf4j
public class SnsService {

    private final SnsClient snsClient;

    @Value("${aws.sns.order-topic-arn}")
    private String orderTopicArn;

    public void publishOrderConfirmation(Order order) {
        if (orderTopicArn == null || orderTopicArn.isEmpty()) {
            log.warn("SNS topic ARN not configured, skipping notification");
            return;
        }

        try {
            String subject = "Order Confirmation - " + order.getOrderNumber();
            String message = buildOrderConfirmationMessage(order);

            PublishRequest publishRequest = PublishRequest.builder()
                    .topicArn(orderTopicArn)
                    .subject(subject)
                    .message(message)
                    .build();

            snsClient.publish(publishRequest);

            log.info("Order confirmation published to SNS: {}", order.getOrderNumber());

        } catch (Exception e) {
            log.error("Failed to publish order confirmation to SNS", e);
            // Don't throw exception
        }
    }

    public void publishOrderStatusUpdate(Order order, String oldStatus) {
        if (orderTopicArn == null || orderTopicArn.isEmpty()) {
            return;
        }

        try {
            String subject = "Order Status Update - " + order.getOrderNumber();
            String message = String.format(
                    "Your order %s status has been updated from %s to %s.%nTotal: $%.2f",
                    order.getOrderNumber(),
                    oldStatus,
                    order.getStatus().name(),
                    order.getTotal()
            );

            PublishRequest publishRequest = PublishRequest.builder()
                    .topicArn(orderTopicArn)
                    .subject(subject)
                    .message(message)
                    .build();

            snsClient.publish(publishRequest);

            log.info("Order status update published to SNS: {}", order.getOrderNumber());

        } catch (Exception e) {
            log.error("Failed to publish order status update to SNS", e);
        }
    }

    public void publishMessage(String topicArn, String subject, String message) {
        try {
            PublishRequest publishRequest = PublishRequest.builder()
                    .topicArn(topicArn)
                    .subject(subject)
                    .message(message)
                    .build();

            snsClient.publish(publishRequest);

            log.info("Message published to SNS topic: {}", topicArn);

        } catch (Exception e) {
            log.error("Failed to publish message to SNS", e);
            throw new RuntimeException("Failed to publish message to SNS", e);
        }
    }

    private String buildOrderConfirmationMessage(Order order) {
        return String.format(
                "Thank you for your order!%n%n" +
                        "Order Number: %s%n" +
                        "Order Date: %s%n" +
                        "Total Amount: $%.2f%n" +
                        "Status: %s%n%n" +
                        "Shipping Address: %s%n%n" +
                        "We will notify you when your order is shipped.",
                order.getOrderNumber(),
                order.getCreatedAt(),
                order.getTotal(),
                order.getStatus().name(),
                order.getShippingAddress()
        );
    }
}
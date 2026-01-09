package com.cloudmartbackend.cloudmart.service;

import com.cloudmartbackend.cloudmart.domain.entity.Order;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;

import java.util.HashMap;
import java.util.Map;

@Service
@RequiredArgsConstructor
@Slf4j
public class SqsService {

    private final SqsClient sqsClient;
    private final ObjectMapper objectMapper;

    @Value("${aws.sqs.order-queue-url}")
    private String orderQueueUrl;

    public void sendOrderMessage(Order order) {
        if (orderQueueUrl == null || orderQueueUrl.isEmpty()) {
            log.warn("SQS queue URL not configured, skipping message send");
            return;
        }
        try {
            Map<String, Object> message = new HashMap<>();
            message.put("orderId", order.getId());
            message.put("orderNumber", order.getOrderNumber());
            message.put("userId", order.getUser().getId());
            message.put("total", order.getTotal());
            message.put("status", order.getStatus().name());
            message.put("timestamp", System.currentTimeMillis());

            String messageBody = objectMapper.writeValueAsString(message);

            SendMessageRequest sendMsgRequest = SendMessageRequest.builder()
                    .queueUrl(orderQueueUrl)
                    .messageBody(messageBody)
                    .build();

            sqsClient.sendMessage(sendMsgRequest);

            log.info("Order message sent to SQS: {}", order.getOrderNumber());

        } catch (Exception e) {
            log.error("Failed to send order message to SQS", e);
            // Don't throw exception - order is already created
        }
    }

    public void sendMessage(String queueUrl, String message) {
        try {
            SendMessageRequest sendMsgRequest = SendMessageRequest.builder()
                    .queueUrl(queueUrl)
                    .messageBody(message)
                    .build();

            sqsClient.sendMessage(sendMsgRequest);

            log.info("Message sent to SQS: {}", queueUrl);

        } catch (Exception e) {
            log.error("Failed to send message to SQS", e);
            throw new RuntimeException("Failed to send message to SQS", e);
        }
    }
}

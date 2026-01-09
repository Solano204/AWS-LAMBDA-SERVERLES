package com.appsdeveloperblog.aws.datatransformation.lambda;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.LambdaLogger;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyRequestEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyResponseEvent;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

public class PostHandler implements RequestHandler<APIGatewayProxyRequestEvent, APIGatewayProxyResponseEvent> {

    private static final ObjectMapper objectMapper = new ObjectMapper();

    @Override
    public APIGatewayProxyResponseEvent handleRequest(APIGatewayProxyRequestEvent input, Context context) {
        LambdaLogger logger = context.getLogger();

        try {
            logger.log("=== LAMBDA STARTED ===");
            logger.log("Request body: " + input.getBody());

            // Parse the incoming request
            Map<String, Object> requestBody = objectMapper.readValue(input.getBody(), Map.class);
            logger.log("Parsed request: " + requestBody);

            // Create response object
            Map<String, Object> responseData = new HashMap<>();
            responseData.put("id", UUID.randomUUID().toString());
            responseData.put("lastName", "Solano");
            responseData.put("status", "created");
            responseData.put("message", "User created successfully");
            responseData.put("clientName", requestBody.get("clientName"));
            responseData.put("clientEmail", requestBody.get("clientEmail"));

            // Convert to JSON string using Jackson
            String responseBody = objectMapper.writeValueAsString(responseData);
            logger.log("Response: " + responseBody);

            Map<String, String> headers = new HashMap<>();
            headers.put("Content-Type", "application/json");
            headers.put("Access-Control-Allow-Origin", "*");

            return new APIGatewayProxyResponseEvent()
                    .withStatusCode(200)
                    .withBody(responseBody)
                    .withHeaders(headers);

        } catch (Exception e) {
            logger.log("ERROR: " + e.getMessage());
            e.printStackTrace();

            Map<String, String> errorResponse = new HashMap<>();
            errorResponse.put("error", e.getMessage());
            errorResponse.put("type", e.getClass().getSimpleName());

            try {
                String errorBody = objectMapper.writeValueAsString(errorResponse);

                Map<String, String> headers = new HashMap<>();
                headers.put("Content-Type", "application/json");
                headers.put("Access-Control-Allow-Origin", "*");

                return new APIGatewayProxyResponseEvent()
                        .withStatusCode(500)
                        .withBody(errorBody)
                        .withHeaders(headers);
            } catch (Exception jsonError) {
                return new APIGatewayProxyResponseEvent()
                        .withStatusCode(500)
                        .withBody("{\"error\":\"Internal server error\"}")
                        .withHeaders(Map.of("Content-Type", "application/json"));
            }
        }
    }
}
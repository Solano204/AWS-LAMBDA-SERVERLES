package com.cloudmartbackend.cloudmart.service;


import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueResponse;

import java.util.HashMap;
import java.util.Map;

@Service
@RequiredArgsConstructor
@Slf4j
public class SecretsManagerService {

    private final SecretsManagerClient secretsManagerClient;
    private final ObjectMapper objectMapper;

    @Value("${aws.secrets.enabled}")
    private boolean secretsEnabled;

    @Value("${aws.secrets.db-secret-name}")
    private String dbSecretName;

    public Map<String, String> getDatabaseCredentials() {
        if (!secretsEnabled) {
            log.info("Secrets Manager is disabled, using local credentials");
            return new HashMap<>();
        }

        try {
            GetSecretValueRequest getSecretValueRequest = GetSecretValueRequest.builder()
                    .secretId(dbSecretName)
                    .build();

            GetSecretValueResponse getSecretValueResponse =
                    secretsManagerClient.getSecretValue(getSecretValueRequest);

            String secret = getSecretValueResponse.secretString();

            JsonNode secretNode = objectMapper.readTree(secret);

            Map<String, String> credentials = new HashMap<>();
            credentials.put("username", secretNode.get("username").asText());
            credentials.put("password", secretNode.get("password").asText());
            credentials.put("host", secretNode.get("host").asText());
            credentials.put("port", secretNode.get("port").asText());
            credentials.put("database", secretNode.get("database").asText());

            log.info("Database credentials retrieved from Secrets Manager");

            return credentials;

        } catch (Exception e) {
            log.error("Failed to retrieve database credentials from Secrets Manager", e);
            throw new RuntimeException("Failed to retrieve database credentials", e);
        }
    }

    public String getSecret(String secretName) {
        if (!secretsEnabled) {
            log.warn("Secrets Manager is disabled");
            return null;
        }

        try {
            GetSecretValueRequest getSecretValueRequest = GetSecretValueRequest.builder()
                    .secretId(secretName)
                    .build();

            GetSecretValueResponse getSecretValueResponse =
                    secretsManagerClient.getSecretValue(getSecretValueRequest);

            return getSecretValueResponse.secretString();

        } catch (Exception e) {
            log.error("Failed to retrieve secret: {}", secretName, e);
            throw new RuntimeException("Failed to retrieve secret", e);
        }
    }
}
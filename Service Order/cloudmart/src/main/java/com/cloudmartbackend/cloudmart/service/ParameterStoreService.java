package com.cloudmartbackend.cloudmart.service;


import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.ssm.SsmClient;
import software.amazon.awssdk.services.ssm.model.GetParameterRequest;
import software.amazon.awssdk.services.ssm.model.GetParameterResponse;
import software.amazon.awssdk.services.ssm.model.ParameterNotFoundException;

import java.util.HashMap;
import java.util.Map;

@Service
@RequiredArgsConstructor
@Slf4j
public class ParameterStoreService {

    private final SsmClient ssmClient;

    @Value("${aws.parameter-store.enabled}")
    private boolean parameterStoreEnabled;

    private final Map<String, String> parameterCache = new HashMap<>();



    public String getParameter(String parameterName) {
        if (!parameterStoreEnabled) {
            log.debug("Parameter Store is disabled");
            return null;
        }

        // Check cache first
        if (parameterCache.containsKey(parameterName)) {
            return parameterCache.get(parameterName);
        }

        try {
            GetParameterRequest parameterRequest = GetParameterRequest.builder()
                    .name(parameterName)
                    .withDecryption(true)
                    .build();

            GetParameterResponse parameterResponse = ssmClient.getParameter(parameterRequest);

            String value = parameterResponse.parameter().value();
            parameterCache.put(parameterName, value);

            log.info("Parameter retrieved from Parameter Store: {}", parameterName);

            return value;

        } catch (ParameterNotFoundException e) {
            log.warn("Parameter not found: {}", parameterName);
            return null;
        } catch (Exception e) {
            log.error("Failed to retrieve parameter: {}", parameterName, e);
            throw new RuntimeException("Failed to retrieve parameter", e);
        }
    }

    public String getParameter(String parameterName, String defaultValue) {
        String value = getParameter(parameterName);
        return value != null ? value : defaultValue;
    }

    public boolean getBooleanParameter(String parameterName, boolean defaultValue) {
        String value = getParameter(parameterName);
        if (value == null) {
            return defaultValue;
        }
        return Boolean.parseBoolean(value);
    }

    public int getIntParameter(String parameterName, int defaultValue) {
        String value = getParameter(parameterName);
        if (value == null) {
            return defaultValue;
        }
        try {
            return Integer.parseInt(value);
        } catch (NumberFormatException e) {
            log.warn("Invalid integer parameter: {}", parameterName);
            return defaultValue;
        }
    }

    public void clearCache() {
        parameterCache.clear();
        log.info("Parameter cache cleared");
    }
}
package com.appsdeveloperblog.aws.lambda;

/**
 * Utility class for handling environment variables.
 *
 * NOTE: This version is for Terraform deployments.
 * Terraform passes plain-text values directly to Lambda environment variables.
 * AWS automatically encrypts these at rest, so manual KMS decryption is not needed.
 */
public class Utils {

    /**
     * Retrieves an environment variable value.
     *
     * @param name The name of the environment variable
     * @return The value of the environment variable, or null if not found
     */
    public static String decryptKey(String name) {
        // Terraform passes actual values directly - no decryption needed
        // AWS encrypts Lambda environment variables at rest automatically
        String value = System.getenv(name);

        if (value == null || value.trim().isEmpty()) {
            throw new RuntimeException("Environment variable '" + name + "' is not set or is empty");
        }

        return value.trim();
    }
}
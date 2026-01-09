package com.appsdeveloperblog.aws.datatransformation.lambda;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.LambdaLogger; // Pro Tip: Use Logger
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

public class PostHandler implements RequestHandler<Map<String, String>, Map<String, String>> {

    public Map<String, String> handleRequest(final Map<String, String> input, final Context context) {
        LambdaLogger logger = context.getLogger();

        // 1. READ "NOMBRE" (Not firstName)
        // API Gateway has already renamed "clientName" to "nombre" for us.
        String internalName = input.get("nombre");
        String country = input.get("country");

        // Log the clean data (Professional Practice)
        logger.log("Internal Processing for: " + internalName);

        // 2. LOGIC
        Map<String, String> response = new HashMap<>();
        response.put("id", UUID.randomUUID().toString());

        // 3. RETURN "LASTNAME" (Internal Name)
        // We return "lastName", but the Client will see "apellido"
        response.put("lastName", "Solano");
        response.put("status", "created");

        return response;
    }
}
package com.cloudmartbackend.cloudmart.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.servers.Server;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.ArrayList;
import java.util.List;

@Configuration
public class SwaggerConfig {

    @Value("${server.port:8080}")
    private String serverPort;

    @Value("${app.swagger.servers:}")
    private String swaggerServers;

    @Bean
    public OpenAPI customOpenAPI() {
        final String securitySchemeName = "Bearer Authentication";

        return new OpenAPI()
                .servers(getServersList())
                .info(new Info()
                        .title("CloudMart Backend API")
                        .version("1.0.0")
                        .description("Complete API documentation for CloudMart Application with 40+ endpoints")
                        .contact(new Contact()
                                .name("CloudMart Team")
                                .email("support@cloudmart.com")))
                .addSecurityItem(new SecurityRequirement().addList(securitySchemeName))
                .components(new Components()
                        .addSecuritySchemes(securitySchemeName,
                                new SecurityScheme()
                                        .name(securitySchemeName)
                                        .type(SecurityScheme.Type.HTTP)
                                        .scheme("bearer")
                                        .bearerFormat("JWT")
                                        .description("Enter JWT token")));
    }

    private List<Server> getServersList() {
        List<Server> servers = new ArrayList<>();

        // If custom servers are defined in application.yml, use them
        if (swaggerServers != null && !swaggerServers.isEmpty()) {
            String[] serverUrls = swaggerServers.split(",");
            for (String url : serverUrls) {
                servers.add(new Server().url(url.trim()).description("Configured Server"));
            }
        } else {
            // Default servers
            servers.add(new Server()
                    .url("http://localhost:" + serverPort)
                    .description("Local Development Server"));
        }

        return servers;
    }
}
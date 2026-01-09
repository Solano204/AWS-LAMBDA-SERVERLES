package com.cloudmartbackend.cloudmart.config;


import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.ApplicationListener;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
@Slf4j
public class ApplicationStartupListener implements ApplicationListener<ApplicationReadyEvent> {

    private final Environment environment;


    @Override
    public void onApplicationEvent(ApplicationReadyEvent event) {
        String port = environment.getProperty("server.port");
        String profile = environment.getProperty("spring.profiles.active");

        log.info("=".repeat(60));
        log.info("CloudMart Backend Application Started Successfully!");
        log.info("Profile: {}", profile);
        log.info("Port: {}", port);
        log.info("API Documentation: http://localhost:{}/swagger-ui.html", port);
        log.info("=".repeat(60));
    }
}
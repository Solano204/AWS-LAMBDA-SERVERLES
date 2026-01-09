package com.cloudmartbackend.cloudmart.service;


import com.cloudmartbackend.cloudmart.exception.FileUploadException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;

import java.io.IOException;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
@Slf4j
public class S3Service {

    private final S3Client s3Client;

    @Value("${aws.s3.bucket-name}")
    private String bucketName;

    @Value("${aws.s3.product-images-prefix}")
    private String productImagesPrefix;

    @Value("${app.upload.allowed-extensions}")
    private String allowedExtensions;

    @Value("${app.upload.max-file-size}")
    private long maxFileSize;


    public String uploadProductImage(MultipartFile file) {
        if (file.isEmpty()) {
            throw new FileUploadException("File is empty");
        }

        if (file.getSize() > maxFileSize) {
            throw new FileUploadException("File size exceeds maximum allowed size");
        }

        String originalFilename = file.getOriginalFilename();
        if (originalFilename == null) {
            throw new FileUploadException("Invalid filename");
        }

        String fileExtension = getFileExtension(originalFilename);
        if (!isAllowedExtension(fileExtension)) {
            throw new FileUploadException("File type not allowed. Allowed types: " + allowedExtensions);
        }

        try {
            String fileName = productImagesPrefix + UUID.randomUUID() + "." + fileExtension;

            PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                    .bucket(bucketName)
                    .key(fileName)
                    .contentType(file.getContentType())
                    .build();

            s3Client.putObject(putObjectRequest, RequestBody.fromBytes(file.getBytes()));

            String imageUrl = String.format("https://%s.s3.amazonaws.com/%s", bucketName, fileName);

            log.info("Image uploaded to S3: {}", imageUrl);

            return imageUrl;

        } catch (IOException e) {
            log.error("Failed to upload image to S3", e);
            throw new FileUploadException("Failed to upload image");
        }
    }

    public void deleteProductImage(String imageUrl) {
        try {
            String key = extractKeyFromUrl(imageUrl);

            DeleteObjectRequest deleteObjectRequest = DeleteObjectRequest.builder()
                    .bucket(bucketName)
                    .key(key)
                    .build();

            s3Client.deleteObject(deleteObjectRequest);

            log.info("Image deleted from S3: {}", imageUrl);

        } catch (Exception e) {
            log.error("Failed to delete image from S3: {}", imageUrl, e);
            // Don't throw exception - deletion failure shouldn't stop the operation
        }
    }

    private String getFileExtension(String filename) {
        int lastDotIndex = filename.lastIndexOf('.');
        if (lastDotIndex == -1) {
            return "";
        }
        return filename.substring(lastDotIndex + 1).toLowerCase();
    }

    private boolean isAllowedExtension(String extension) {
        List<String> allowed = Arrays.asList(allowedExtensions.split(","));
        return allowed.contains(extension.toLowerCase());
    }

    private String extractKeyFromUrl(String url) {
        // Extract key from URL like: https://bucket.s3.amazonaws.com/key
        String[] parts = url.split(".amazonaws.com/");
        if (parts.length > 1) {
            return parts[1];
        }
        return url;
    }
}
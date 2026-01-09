package com.cloudmartbackend.cloudmart.service;


import com.cloudmartbackend.cloudmart.domain.entity.Product;
import com.cloudmartbackend.cloudmart.domain.entity.User;
import com.cloudmartbackend.cloudmart.dto.request.ProductRequest;
import com.cloudmartbackend.cloudmart.dto.response.ProductResponse;
import com.cloudmartbackend.cloudmart.exception.ResourceNotFoundException;
import com.cloudmartbackend.cloudmart.exception.UnauthorizedException;
import com.cloudmartbackend.cloudmart.repository.ProductRepository;
import com.cloudmartbackend.cloudmart.security.SecurityUtils;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.math.BigDecimal;
import java.util.List;

@Service
@RequiredArgsConstructor
@Slf4j
public class ProductService {

    private final ProductRepository productRepository;
    private final S3Service s3Service;
    private final SecurityUtils securityUtils;

    @Transactional
    public ProductResponse createProduct(ProductRequest request, MultipartFile image) {
        User seller = securityUtils.getCurrentUser();

        if (seller.getRole() != User.UserRole.SELLER && seller.getRole() != User.UserRole.ADMIN) {
            throw new UnauthorizedException("Only sellers can create products");
        }

        Product product = Product.builder()
                .name(request.getName())
                .description(request.getDescription())
                .price(request.getPrice())
                .stock(request.getStock())
                .category(request.getCategory())
                .brand(request.getBrand())
                .status(Product.ProductStatus.ACTIVE)
                .seller(seller)
                .build();

        // Upload image to S3 if provided
        if (image != null && !image.isEmpty()) {
            String imageUrl = s3Service.uploadProductImage(image);
            product.setImageUrl(imageUrl);
        }

        Product savedProduct = productRepository.save(product);
        log.info("Product created: {}", savedProduct.getName());

        return ProductResponse.fromEntity(savedProduct);
    }

    @Transactional(readOnly = true)
    public ProductResponse getProductById(Long id) {
        Product product = productRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Product not found with id: " + id));
        return ProductResponse.fromEntity(product);
    }

    @Transactional(readOnly = true)
    public Page<ProductResponse> getAllProducts(Pageable pageable) {
        return productRepository.findByStatus(Product.ProductStatus.ACTIVE, pageable)
                .map(ProductResponse::fromEntity);
    }

    @Transactional(readOnly = true)
    public Page<ProductResponse> getProductsByCategory(String category, Pageable pageable) {
        return productRepository.findByCategoryAndStatus(category, Product.ProductStatus.ACTIVE, pageable)
                .map(ProductResponse::fromEntity);
    }

    @Transactional(readOnly = true)
    public Page<ProductResponse> searchProducts(String keyword, Pageable pageable) {
        return productRepository.searchByKeyword(keyword, pageable)
                .map(ProductResponse::fromEntity);
    }

    @Transactional(readOnly = true)
    public Page<ProductResponse> getProductsByPriceRange(BigDecimal minPrice, BigDecimal maxPrice, Pageable pageable) {
        return productRepository.findByPriceBetweenAndStatus(minPrice, maxPrice, Product.ProductStatus.ACTIVE, pageable)
                .map(ProductResponse::fromEntity);
    }

    @Transactional(readOnly = true)
    public Page<ProductResponse> getMyProducts(Pageable pageable) {
        User seller = securityUtils.getCurrentUser();
        return productRepository.findBySeller(seller, pageable)
                .map(ProductResponse::fromEntity);
    }

    @Transactional(readOnly = true)
    public List<String> getAllCategories() {
        return productRepository.findDistinctCategories();
    }

    @Transactional
    public ProductResponse updateProduct(Long id, ProductRequest request, MultipartFile image) {
        Product product = productRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Product not found with id: " + id));

        User currentUser = securityUtils.getCurrentUser();

        // Only the seller or admin can update
        if (!product.getSeller().getId().equals(currentUser.getId())
                && currentUser.getRole() != User.UserRole.ADMIN) {
            throw new UnauthorizedException("You don't have permission to update this product");
        }

        // Update fields
        if (request.getName() != null) {
            product.setName(request.getName());
        }
        if (request.getDescription() != null) {
            product.setDescription(request.getDescription());
        }
        if (request.getPrice() != null) {
            product.setPrice(request.getPrice());
        }
        if (request.getStock() != null) {
            product.setStock(request.getStock());
            if (request.getStock() > 0 && product.getStatus() == Product.ProductStatus.OUT_OF_STOCK) {
                product.setStatus(Product.ProductStatus.ACTIVE);
            }
        }
        if (request.getCategory() != null) {
            product.setCategory(request.getCategory());
        }
        if (request.getBrand() != null) {
            product.setBrand(request.getBrand());
        }

        // Update image if provided
        if (image != null && !image.isEmpty()) {
            // Delete old image if exists
            if (product.getImageUrl() != null) {
                s3Service.deleteProductImage(product.getImageUrl());
            }
            String imageUrl = s3Service.uploadProductImage(image);
            product.setImageUrl(imageUrl);
        }

        Product savedProduct = productRepository.save(product);
        log.info("Product updated: {}", savedProduct.getId());

        return ProductResponse.fromEntity(savedProduct);
    }

    @Transactional
    public void deleteProduct(Long id) {
        Product product = productRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Product not found with id: " + id));

        User currentUser = securityUtils.getCurrentUser();

        if (!product.getSeller().getId().equals(currentUser.getId())
                && currentUser.getRole() != User.UserRole.ADMIN) {
            throw new UnauthorizedException("You don't have permission to delete this product");
        }

        // Soft delete
        product.setStatus(Product.ProductStatus.DELETED);
        productRepository.save(product);

        log.info("Product deleted (soft delete): {}", id);
    }
}

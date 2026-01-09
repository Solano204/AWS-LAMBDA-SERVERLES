package com.cloudmartbackend.cloudmart.repository;


import com.cloudmartbackend.cloudmart.domain.entity.Product;
import com.cloudmartbackend.cloudmart.domain.entity.User;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.util.List;

@Repository
public interface ProductRepository extends JpaRepository<Product, Long> {

    Page<Product> findByStatus(Product.ProductStatus status, Pageable pageable);

    Page<Product> findByCategoryAndStatus(String category, Product.ProductStatus status, Pageable pageable);

    Page<Product> findBySeller(User seller, Pageable pageable);

    Page<Product> findByPriceBetweenAndStatus(
            BigDecimal minPrice,
            BigDecimal maxPrice,
            Product.ProductStatus status,
            Pageable pageable
    );

    @Query("SELECT p FROM Product p WHERE " +
            "(LOWER(p.name) LIKE LOWER(CONCAT('%', :keyword, '%')) OR " +
            "LOWER(p.description) LIKE LOWER(CONCAT('%', :keyword, '%')) OR " +
            "LOWER(p.category) LIKE LOWER(CONCAT('%', :keyword, '%'))) AND " +
            "p.status = 'ACTIVE'")
    Page<Product> searchByKeyword(@Param("keyword") String keyword, Pageable pageable);

    @Query("SELECT DISTINCT p.category FROM Product p WHERE p.status = 'ACTIVE' ORDER BY p.category")
    List<String> findDistinctCategories();
}
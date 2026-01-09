package com.cloudmartbackend.cloudmart.repository;


import com.cloudmartbackend.cloudmart.domain.entity.OrderItem;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface OrderItemRepository extends JpaRepository<OrderItem, Long> {
    // Basic CRUD operations are inherited from JpaRepository
}
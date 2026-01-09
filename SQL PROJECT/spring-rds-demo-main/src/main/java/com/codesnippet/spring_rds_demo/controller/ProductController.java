package com.codesnippet.spring_rds_demo.controller;

import com.codesnippet.spring_rds_demo.entity.Product;
import com.codesnippet.spring_rds_demo.repository.ProductRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
public class ProductController {

    @Autowired
    private ProductRepository repo;

    @PostMapping("/product")
    public Product save(@RequestBody Product product) {
        return repo.save(product);
    }

    @GetMapping("/products")
    public List<Product> getAll() {
        return repo.findAll();
    }
}

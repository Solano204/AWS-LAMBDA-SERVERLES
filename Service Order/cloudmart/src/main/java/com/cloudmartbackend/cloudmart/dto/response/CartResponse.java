package com.cloudmartbackend.cloudmart.dto.response;


import com.cloudmartbackend.cloudmart.domain.entity.Cart;
import lombok.*;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.stream.Collectors;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class CartResponse {
    private String userId;
    private List<CartItemResponse> items;
    private BigDecimal total;
    private Instant updatedAt;

    public static CartResponse fromEntity(Cart cart) {
        return CartResponse.builder()
                .userId(cart.getUserId())
                .items(cart.getItems().stream()
                        .map(CartItemResponse::fromEntity)
                        .collect(Collectors.toList()))
                .total(cart.calculateTotal())
                .updatedAt(cart.getUpdatedAt())
                .build();
    }
}
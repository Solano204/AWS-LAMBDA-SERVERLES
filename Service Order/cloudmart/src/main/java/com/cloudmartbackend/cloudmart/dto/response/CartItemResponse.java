package com.cloudmartbackend.cloudmart.dto.response;


import com.cloudmartbackend.cloudmart.domain.entity.CartItem;
import lombok.*;

import java.math.BigDecimal;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class CartItemResponse {
    private Long productId;
    private String productName;
    private BigDecimal price;
    private Integer quantity;
    private String imageUrl;
    private Integer availableStock;
    private BigDecimal subtotal;

    public static CartItemResponse fromEntity(CartItem item) {
        return CartItemResponse.builder()
                .productId(item.getProductId())
                .productName(item.getProductName())
                .price(item.getPrice())
                .quantity(item.getQuantity())
                .imageUrl(item.getImageUrl())
                .availableStock(item.getAvailableStock())
                .subtotal(item.getSubtotal())
                .build();
    }
}
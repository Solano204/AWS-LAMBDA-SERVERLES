package com.cloudmartbackend.cloudmart.controller;


import com.cloudmartbackend.cloudmart.dto.request.AddToCartRequest;
import com.cloudmartbackend.cloudmart.dto.response.ApiResponse;
import com.cloudmartbackend.cloudmart.dto.response.CartResponse;
import com.cloudmartbackend.cloudmart.service.CartService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/cart")
@RequiredArgsConstructor
@CrossOrigin(origins = "*", maxAge = 3600)

public class CartController {

    private final CartService cartService;

    @GetMapping
    public ResponseEntity<ApiResponse<CartResponse>> getCart() {
        CartResponse cart = cartService.getCart();
        return ResponseEntity.ok(ApiResponse.success(cart));
    }

    @PostMapping("/items")
    public ResponseEntity<ApiResponse<CartResponse>> addToCart(@Valid @RequestBody AddToCartRequest request) {
        CartResponse cart = cartService.addToCart(request);
        return ResponseEntity.ok(ApiResponse.success("Item added to cart", cart));
    }

    @PutMapping("/items/{productId}")
    public ResponseEntity<ApiResponse<CartResponse>> updateCartItem(
            @PathVariable Long productId,
            @RequestParam int quantity
    ) {
        CartResponse cart = cartService.updateCartItemQuantity(productId, quantity);
        return ResponseEntity.ok(ApiResponse.success("Cart item updated", cart));
    }

    @DeleteMapping("/items/{productId}")
    public ResponseEntity<ApiResponse<CartResponse>> removeFromCart(@PathVariable Long productId) {
        CartResponse cart = cartService.removeFromCart(productId);
        return ResponseEntity.ok(ApiResponse.success("Item removed from cart", cart));
    }

    @DeleteMapping
    public ResponseEntity<ApiResponse<Void>> clearCart() {
        cartService.clearCart();
        return ResponseEntity.ok(ApiResponse.success("Cart cleared", null));
    }

    @PostMapping("/sync")
    public ResponseEntity<ApiResponse<Void>> syncCart() {
        cartService.syncCartWithInventory();
        return ResponseEntity.ok(ApiResponse.success("Cart synced with inventory", null));
    }
}
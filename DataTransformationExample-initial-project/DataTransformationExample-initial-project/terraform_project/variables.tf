"""
CloudMart Shipping Cost Calculator Lambda Function
This Lambda function calculates shipping costs based on order details.
It's called via API Gateway from the React frontend.
"""

import json
import logging
from decimal import Decimal, ROUND_HALF_UP
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Shipping configuration
SHIPPING_CONFIG = {
    'FREE_SHIPPING_THRESHOLD': Decimal('100.00'),
    'STANDARD_RATE': Decimal('9.99'),
    'EXPRESS_RATE': Decimal('19.99'),
    'WEIGHT_THRESHOLD': 10,  # kg
    'HEAVY_ITEM_SURCHARGE': Decimal('15.00'),
    'REGIONS': {
        'US': {
            'STANDARD': Decimal('9.99'),
            'EXPRESS': Decimal('19.99')
        },
        'CA': {
            'STANDARD': Decimal('14.99'),
            'EXPRESS': Decimal('29.99')
        },
        'MX': {
            'STANDARD': Decimal('12.99'),
            'EXPRESS': Decimal('24.99')
        },
        'INTERNATIONAL': {
            'STANDARD': Decimal('24.99'),
            'EXPRESS': Decimal('49.99')
        }
    }
}


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function

    Expected input (POST body):
    {
        "subtotal": 150.00,
        "items": [
            {"productId": 1, "weight": 2.5, "quantity": 1},
            {"productId": 2, "weight": 0.5, "quantity": 3}
        ],
        "shippingMethod": "STANDARD",  // or "EXPRESS"
        "country": "US",
        "zipCode": "10001"
    }

    Returns:
    {
        "statusCode": 200,
        "body": {
            "subtotal": 150.00,
            "shippingCost": 9.99,
            "estimatedDeliveryDays": 5,
            "total": 159.99,
            "freeShippingEligible": false,
            "amountForFreeShipping": 0,
            "breakdown": {...}
        }
    }
    """

    try:
        logger.info(f"Received event: {json.dumps(event)}")

        # Parse request body
        if 'body' in event:
            if isinstance(event['body'], str):
                body = json.loads(event['body'])
            else:
                body = event['body']
        else:
            body = event

        # Validate required fields
        validation_error = validate_request(body)
        if validation_error:
            return error_response(400, validation_error)

        # Extract request data
        subtotal = Decimal(str(body.get('subtotal', 0)))
        items = body.get('items', [])
        shipping_method = body.get('shippingMethod', 'STANDARD').upper()
        country = body.get('country', 'US').upper()
        zip_code = body.get('zipCode', '')

        # Calculate shipping
        result = calculate_shipping(
            subtotal=subtotal,
            items=items,
            shipping_method=shipping_method,
            country=country,
            zip_code=zip_code
        )

        logger.info(f"Calculation result: {result}")

        return success_response(result)

    except ValueError as ve:
        logger.error(f"Validation error: {str(ve)}")
        return error_response(400, str(ve))

    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}", exc_info=True)
        return error_response(500, "Internal server error")


def validate_request(body: Dict[str, Any]) -> str:
    """Validate request body"""

    if not body:
        return "Request body is required"

    if 'subtotal' not in body:
        return "Field 'subtotal' is required"

    try:
        subtotal = Decimal(str(body['subtotal']))
        if subtotal < 0:
            return "Subtotal must be non-negative"
    except (ValueError, TypeError):
        return "Invalid subtotal value"

    if 'items' in body and not isinstance(body['items'], list):
        return "Field 'items' must be an array"

    shipping_method = body.get('shippingMethod', 'STANDARD').upper()
    if shipping_method not in ['STANDARD', 'EXPRESS']:
        return "Invalid shipping method. Must be 'STANDARD' or 'EXPRESS'"

    return None


def calculate_shipping(
        subtotal: Decimal,
        items: list,
        shipping_method: str,
        country: str,
        zip_code: str
) -> Dict[str, Any]:
    """Calculate shipping cost based on order details"""

    # Initialize result
    result = {
        'subtotal': float(subtotal),
        'shippingMethod': shipping_method,
        'country': country,
        'shippingCost': Decimal('0.00'),
        'estimatedDeliveryDays': 0,
        'total': float(subtotal),
        'freeShippingEligible': False,
        'amountForFreeShipping': Decimal('0.00'),
        'breakdown': {}
    }

    # Check for free shipping eligibility
    free_shipping_threshold = SHIPPING_CONFIG['FREE_SHIPPING_THRESHOLD']

    if subtotal >= free_shipping_threshold:
        result['freeShippingEligible'] = True
        result['shippingCost'] = Decimal('0.00')
        result['estimatedDeliveryDays'] = 5 if shipping_method == 'STANDARD' else 2
        result['total'] = float(subtotal)
        result['breakdown']['freeShipping'] = True
        result['breakdown']['reason'] = f"Order over ${free_shipping_threshold}"
        return convert_decimals_to_float(result)

    # Calculate base shipping rate based on country
    region_config = SHIPPING_CONFIG['REGIONS'].get(
        country,
        SHIPPING_CONFIG['REGIONS']['INTERNATIONAL']
    )
    base_rate = region_config[shipping_method]

    # Calculate total weight
    total_weight = calculate_total_weight(items)

    # Add heavy item surcharge if applicable
    heavy_item_surcharge = Decimal('0.00')
    if total_weight > SHIPPING_CONFIG['WEIGHT_THRESHOLD']:
        heavy_item_surcharge = SHIPPING_CONFIG['HEAVY_ITEM_SURCHARGE']

    # Calculate final shipping cost
    shipping_cost = base_rate + heavy_item_surcharge

    # Calculate how much more is needed for free shipping
    amount_for_free = max(Decimal('0.00'), free_shipping_threshold - subtotal)

    # Estimate delivery days
    if shipping_method == 'EXPRESS':
        delivery_days = 1 if country == 'US' else 2
    else:
        if country == 'US':
            delivery_days = 5
        elif country in ['CA', 'MX']:
            delivery_days = 7
        else:
            delivery_days = 14

    # Build breakdown
    breakdown = {
        'baseRate': float(base_rate),
        'totalWeight': float(total_weight),
        'heavyItemSurcharge': float(heavy_item_surcharge),
        'itemCount': len(items)
    }

    # Update result
    result.update({
        'shippingCost': float(shipping_cost),
        'estimatedDeliveryDays': delivery_days,
        'total': float(subtotal + shipping_cost),
        'amountForFreeShipping': float(amount_for_free),
        'breakdown': breakdown
    })

    return convert_decimals_to_float(result)


def calculate_total_weight(items: list) -> Decimal:
    """Calculate total weight of all items"""
    total_weight = Decimal('0.00')

    for item in items:
        weight = Decimal(str(item.get('weight', 0)))
        quantity = int(item.get('quantity', 1))
        total_weight += weight * quantity

    return total_weight


def convert_decimals_to_float(obj: Any) -> Any:
    """Recursively convert Decimal objects to float for JSON serialization"""
    if isinstance(obj, Decimal):
        return float(obj)
    elif isinstance(obj, dict):
        return {k: convert_decimals_to_float(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [convert_decimals_to_float(item) for item in obj]
    return obj


def success_response(data: Dict[str, Any]) -> Dict[str, Any]:
    """Create successful API response"""
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type'
        },
        'body': json.dumps({
            'success': True,
            'data': data
        })
    }


def error_response(status_code: int, message: str) -> Dict[str, Any]:
    """Create error API response"""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type'
        },
        'body': json.dumps({
            'success': False,
            'error': message
        })
    }


# For local testing
if __name__ == '__main__':
    # Test event
    test_event = {
        'body': json.dumps({
            'subtotal': 75.00,
            'items': [
                {'productId': 1, 'weight': 2.5, 'quantity': 1},
                {'productId': 2, 'weight': 0.5, 'quantity': 3}
            ],
            'shippingMethod': 'STANDARD',
            'country': 'US',
            'zipCode': '10001'
        })
    }

    result = lambda_handler(test_event, None)
    print(json.dumps(result, indent=2))
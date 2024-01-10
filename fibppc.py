def fibonacci_pivot_points():
    # Ask for user input
    high = float(input("Enter the day's high price: "))
    low = float(input("Enter the day's low price: "))
    close = float(input("Enter the day's close price: "))

    pivot_point = (high + low + close) / 3

    # Fibonacci ratios
    ratios = [0.382, 0.618, 1.000, 1.382, 1.618]

    # Calculate support and resistance levels
    support_levels = [pivot_point - (high - low) * ratio for ratio in ratios]
    resistance_levels = [pivot_point + (high - low) * ratio for ratio in ratios]

    return pivot_point, support_levels, resistance_levels

# Example usage:
pivot_point, support_levels, resistance_levels = fibonacci_pivot_points()

print(f"Pivot Point: {pivot_point}")
print(f"Support Levels: {support_levels}")
print(f"Resistance Levels: {resistance_levels}")

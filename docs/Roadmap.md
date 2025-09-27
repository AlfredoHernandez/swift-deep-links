# Roadmap

## Rate Limiting Strategies - Future Implementations

The following rate limiting strategies were removed from the current implementation but are planned for future releases:

### Token Bucket Strategy
- **Status**: Planned for a future version
- **Description**: Uses a token bucket algorithm for more flexible rate limiting with burst allowances
- **Use Cases**: 
  - When burst allowances are needed (e.g., allowing 10 requests in 1 second, then 1 per second)
  - Systems that need to handle traffic spikes gracefully
  - More sophisticated rate limiting scenarios
- **Implementation Notes**: Requires token refill logic and bucket capacity management

### Strict Strategy
- **Status**: Planned for a future version
- **Description**: Enforces stricter rate limits (50% of configured limits) for high-security scenarios
- **Use Cases**:
  - High-security applications requiring extra protection
  - Development/testing environments that need stricter limits
  - Compliance scenarios with mandatory rate limiting
- **Implementation Notes**: Simple modification of existing sliding window with reduced limits

### Adaptive Strategy
- **Status**: Planned for a future version
- **Description**: Dynamically adjusts rate limits based on system load and user behavior
- **Use Cases**:
  - Systems with variable load patterns
  - User-specific rate limiting based on trust levels
  - ML-driven rate limiting optimization
- **Implementation Notes**: Requires metrics collection and adaptive algorithm implementation

### Distributed Strategy
- **Status**: Planned for a future version
- **Description**: Coordinates rate limiting across multiple app instances or services
- **Use Cases**:
  - Multi-instance applications
  - Microservices architectures
  - Cross-platform rate limiting
- **Implementation Notes**: Requires distributed coordination mechanism (Redis, etc.)

---

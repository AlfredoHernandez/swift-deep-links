# Swift Deep Link - Core Package Architecture

This document contains the specific architecture diagram of the Swift Deep Link Core package, showing the internal structure and interactions between the main components.

## Core Architecture Diagram

```mermaid
graph TB
    subgraph "Core Package Architecture"
        subgraph "Entry Point"
            URL["Deep Link URL"]
        end
        
        subgraph "Main Coordinator"
            Coordinator["DeepLinkCoordinator<br/>Main Orchestrator"]
            CoordinatorProps["Properties:<br/>• routing: DeepLinkRouting<br/>• handler: DeepLinkHandler<br/>• middlewareCoordinator<br/>• routeExecutionDelay<br/>• delegate"]
            CoordinatorMethods["Methods:<br/>• handle(url: URL)<br/>• add(middleware)<br/>• removeMiddleware(type)"]
        end
        
        subgraph "Routing System"
            RoutingProtocol["DeepLinkRouting Protocol<br/>• route(from: URL) async throws -> [Route]"]
            DefaultRouting["DefaultDeepLinkRouting<br/>• Tries multiple parsers<br/>• Returns first success<br/>• Throws routeNotFound"]
            Parsers["Parsers Array<br/>[DeepLinkParser]"]
        end
        
        subgraph "Parser System"
            ParserProtocol["DeepLinkParser Protocol<br/>• parse(from: URL) throws -> [Route]"]
            Parser1["Parser 1<br/>ProfileParser"]
            Parser2["Parser 2<br/>ProductParser"]
            Parser3["Parser N<br/>SettingsParser"]
        end
        
        subgraph "Handler System"
            HandlerProtocol["DeepLinkHandler Protocol<br/>• handle(route: Route) async throws"]
            HandlerImpl["Handler Implementation<br/>AppDeepLinkHandler"]
        end
        
        subgraph "Route System"
            RouteProtocol["DeepLinkRoute Protocol<br/>• id: String"]
            Route1["ProfileRoute"]
            Route2["ProductRoute"]
            Route3["SettingsRoute"]
        end
        
        subgraph "Result System"
            Result["DeepLinkResult<br/>• originalURL: URL<br/>• processedURL: URL?<br/>• routes: [Route]<br/>• executionTime: TimeInterval<br/>• errors: [Error]<br/>• successfulRoutes: Int<br/>• failedRoutes: Int"]
            ResultProtocol["DeepLinkResultProtocol<br/>• wasSuccessful: Bool<br/>• hasRoutes: Bool<br/>• hasErrors: Bool<br/>• summary: String"]
        end
        
        subgraph "Supporting Components"
            DeepLinkURL["DeepLinkURL<br/>URL Wrapper with<br/>• host: String<br/>• queryParameters: [String: String]"]
            DeepLinkError["DeepLinkError<br/>Comprehensive Error Types"]
            Logger["OSLog Logger<br/>Subsystem: swift-deep-link"]
        end
        
        subgraph "Delegate System"
            CoordinatorDelegate["DeepLinkCoordinatorDelegate<br/>• willProcess(url)<br/>• didProcess(url, result)<br/>• didFailProcessing(url, error)"]
        end
    end
    
    %% Main Flow
    URL --> Coordinator
    Coordinator --> CoordinatorProps
    Coordinator --> CoordinatorMethods
    
    %% Coordinator orchestrates routing and handling
    Coordinator --> RoutingProtocol
    Coordinator --> HandlerProtocol
    Coordinator --> CoordinatorDelegate
    
    %% Routing system
    RoutingProtocol --> DefaultRouting
    DefaultRouting --> Parsers
    Parsers --> ParserProtocol
    
    %% Parser implementations
    ParserProtocol --> Parser1
    ParserProtocol --> Parser2
    ParserProtocol --> Parser3
    
    %% Parsers create routes
    Parser1 --> Route1
    Parser2 --> Route2
    Parser3 --> Route3
    
    %% Routes conform to protocol
    Route1 --> RouteProtocol
    Route2 --> RouteProtocol
    Route3 --> RouteProtocol
    
    %% Handler processes routes
    HandlerProtocol --> HandlerImpl
    HandlerImpl --> RouteProtocol
    
    %% Result system
    Coordinator --> Result
    Result --> ResultProtocol
    
    %% Supporting components
    ParserProtocol --> DeepLinkURL
    DefaultRouting --> DeepLinkURL
    Coordinator --> DeepLinkError
    RoutingProtocol --> DeepLinkError
    HandlerProtocol --> DeepLinkError
    Coordinator --> Logger
    
    %% Styling
    classDef coordinator fill:#e1f5fe,stroke:#01579b,stroke-width:3px
    classDef protocol fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef implementation fill:#e8f5e8,stroke:#1b5e20,stroke-width:2px
    classDef route fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef result fill:#fce4ec,stroke:#880e4f,stroke-width:2px
    classDef support fill:#f1f8e9,stroke:#33691e,stroke-width:2px
    classDef delegate fill:#e0f2f1,stroke:#004d40,stroke-width:2px
    
    class Coordinator,CoordinatorProps,CoordinatorMethods coordinator
    class RoutingProtocol,ParserProtocol,HandlerProtocol,RouteProtocol,ResultProtocol,CoordinatorDelegate protocol
    class DefaultRouting,Parsers,Parser1,Parser2,Parser3,HandlerImpl implementation
    class Route1,Route2,Route3 route
    class Result,ResultProtocol result
    class DeepLinkURL,DeepLinkError,Logger support
    class CoordinatorDelegate delegate
```

## Core Components Explanation

### 🔵 DeepLinkCoordinator (Blue)
**The central orchestrator of the system**

- **Purpose**: Coordinates the entire deep link processing flow
- **Responsibilities**:
  - Process URLs through the middleware system
  - Route URLs using the routing system
  - Execute handlers for each found route
  - Manage delegates for notifications
  - Provide execution metrics

- **Key Properties**:
  - `routing`: Routing system
  - `handler`: Route handler
  - `middlewareCoordinator`: Middleware coordinator
  - `routeExecutionDelay`: Delay between route executions
  - `delegate`: Delegate for notifications

### 🟣 Protocols (Purple)
**Interfaces that define contracts**

- **DeepLinkRouting**: Defines how to route URLs to routes
- **DeepLinkParser**: Defines how to parse URLs into routes
- **DeepLinkHandler**: Defines how to handle specific routes
- **DeepLinkRoute**: Defines the structure of a route
- **DeepLinkResultProtocol**: Defines result properties
- **DeepLinkCoordinatorDelegate**: Defines coordinator notifications

### 🟢 Implementations (Green)
**Concrete implementations of protocols**

- **DefaultDeepLinkRouting**: Standard implementation that tries multiple parsers
- **Parsers Array**: Collection of specific parsers
- **Parser Implementations**: Concrete parsers (Profile, Product, Settings)
- **Handler Implementation**: Concrete handler implementation

### 🟠 Route System (Orange)
**Typed and structured routes**

- **Route Types**: Specific route types (Profile, Product, Settings)
- **Route Protocol**: Base protocol that all routes must implement
- **Route ID**: Unique identifier for each route

### 🔴 Result System (Pink)
**Complete processing information**

- **DeepLinkResult**: Complete structure with metrics and state
- **Result Properties**: Convenience properties for analysis
- **Execution Metrics**: Execution time and success/failure counts

### 🟢 Supporting Components (Light Green)
**Utilities and auxiliary components**

- **DeepLinkURL**: URL wrapper with extended functionality
- **DeepLinkError**: Comprehensive and localized error types
- **OSLog Logger**: Integrated logging system

### 🟢 Delegate System (Teal)
**Notifications and callbacks**

- **CoordinatorDelegate**: Notifications about processing status
- **Lifecycle Methods**: willProcess, didProcess, didFailProcessing

## Core Processing Flow

1. **URL Entry** → URL enters DeepLinkCoordinator
2. **Middleware Processing** → URL is processed through middleware
3. **Routing** → DefaultDeepLinkRouting tries parsers in sequence
4. **Parsing** → Successful parser converts URL into routes
5. **Route Creation** → Typed route objects are created
6. **Handler Execution** → Handler processes each found route
7. **Result Generation** → DeepLinkResult is generated with complete metrics
8. **Delegate Notifications** → Result is notified to delegates

## Key Core Features

- **🔒 Type Safety**: Generic-based design with `Route: DeepLinkRoute`
- **⚡ Async/Await**: Full support for modern concurrency
- **🧪 Protocol-Oriented**: Protocol-based design for easy testing
- **📊 Comprehensive Results**: Detailed execution metrics
- **🔔 Delegate Pattern**: Reactive state notifications
- **🛡️ Error Handling**: Robust error handling at each layer
- **📝 Logging**: Integrated OSLog logging for debugging

## Benefits of this Core Architecture

- **Separation of Concerns**: Each component has a specific responsibility
- **Extensibility**: Easy to add new parsers and handlers
- **Testability**: Protocols allow easy mocking and testing
- **Observability**: Complete metrics and detailed logging
- **Thread Safety**: Concurrency-safe design
- **Performance**: Efficient processing with configurable delays

## See Also

- [Complete Architecture Diagram](./architecture-diagram.md) - Complete system overview
- [How to Use DeepLink](./how-to-use-deeplink-en.md) - Implementation guide
- [API Reference](./api-reference-en.md) - Detailed API documentation
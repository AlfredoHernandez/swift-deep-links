# Referencia de API

Documentación completa de la API para la librería DeepLink.

## Componentes Principales

### DeepLinkRoute

El protocolo base que todos los tipos de ruta deben conformar.

```swift
public protocol DeepLinkRoute {
    var id: String { get }
}
```

**Requisitos:**
- `id: String` - Un identificador único para la ruta

### DeepLinkURL

Una representación estructurada de una URL de deep link con componentes parseados.

```swift
public struct DeepLinkURL {
    public let url: URL
    public let scheme: String
    public let host: String
    public let path: String
    public let queryParameters: [String: String]
    
    public init(url: URL) throws(DeepLinkError)
}
```

**Propiedades:**
- `url: URL` - La URL original
- `scheme: String` - El esquema de la URL (ej., "miapp")
- `host: String` - El host de la URL (ej., "profile")
- `path: String` - El componente de ruta de la URL
- `queryParameters: [String: String]` - Parámetros de consulta como diccionario

**Métodos:**
- `init(url: URL)` - Crea un nuevo DeepLinkURL desde una URL estándar

### DeepLinkError

Tipos de error para operaciones de deep link.

```swift
public enum DeepLinkError: Error, Equatable {
    case invalidURL(URL)
    case unsupportedHost(String)
    case routeNotFound(String)
    case missingRequiredParameter(String)
}
```

**Casos:**
- `invalidURL(URL)` - La URL está malformada o le faltan componentes requeridos
- `unsupportedHost(String)` - El host de la URL no es compatible
- `routeNotFound(String)` - Ningún parser pudo manejar la URL
- `missingRequiredParameter(String)` - Falta un parámetro requerido

## Parsing

### DeepLinkParser

Protocolo para parsear URLs en objetos de ruta.

```swift
public protocol DeepLinkParser {
    associatedtype Route: DeepLinkRoute
    
    func parse(from url: URL) throws -> [Route]
}
```

**Requisitos:**
- `parse(from url: URL) throws -> [Route]` - Parsear una URL en objetos de ruta

### QueryParameterParser

Protocolo para parsear parámetros de consulta en objetos fuertemente tipados.

```swift
public protocol QueryParameterParser {
    func parse<T: Decodable>(_ type: T.Type, from parameters: [String: String]) throws -> T
}
```

**Requisitos:**
- `parse<T: Decodable>(_ type: T.Type, from parameters: [String: String]) throws -> T` - Parsear parámetros en un tipo Decodable

### JSONQueryParameterParser

Implementación por defecto de QueryParameterParser usando codificación/decodificación JSON.

```swift
public final class JSONQueryParameterParser: QueryParameterParser {
    public init(jsonDecoder: JSONDecoder = JSONDecoder())
    
    public func parse<T: Decodable>(_ type: T.Type, from parameters: [String: String]) throws -> T
}
```

**Métodos:**
- `init(jsonDecoder: JSONDecoder)` - Inicializar con un decodificador JSON personalizado
- `parse<T: Decodable>(_ type: T.Type, from parameters: [String: String]) throws -> T` - Parsear parámetros usando decodificación JSON

## Routing

### DeepLinkRouting

Protocolo para enrutar URLs a parsers apropiados.

```swift
public protocol DeepLinkRouting {
    associatedtype Route: DeepLinkRoute
    
    func route(from url: URL) async throws -> [Route]
}
```

**Requisitos:**
- `route(from url: URL) async throws -> [Route]` - Enrutar una URL a parsers apropiados

### DefaultDeepLinkRouting

Implementación por defecto que intenta múltiples parsers hasta que uno tenga éxito.

```swift
public final class DefaultDeepLinkRouting<Route: DeepLinkRoute>: DeepLinkRouting {
    public init(parsers: [any DeepLinkParser<Route>])
    
    public func route(from url: URL) async throws -> [Route]
}
```

**Métodos:**
- `init(parsers: [any DeepLinkParser<Route>])` - Inicializar con un array de parsers
- `route(from url: URL) async throws -> [Route]` - Intentar parsers en secuencia hasta que uno tenga éxito

## Handling

### DeepLinkHandler

Protocolo para manejar objetos de ruta parseados.

```swift
public protocol DeepLinkHandler {
    associatedtype Route: DeepLinkRoute
    
    func handle(_ route: Route) async throws
}
```

**Requisitos:**
- `handle(_ route: Route) async throws` - Manejar una ruta parseada

## Coordinación

### DeepLinkCoordinator

Orquestador principal que coordina el flujo de manejo de deep links.

```swift
public final class DeepLinkCoordinator<Route: DeepLinkRoute>: @unchecked Sendable {
    public init(routing: any DeepLinkRouting<Route>, handler: any DeepLinkHandler<Route>)
    
    public func handle(url: URL) async
}
```

**Métodos:**
- `init(routing: any DeepLinkRouting<Route>, handler: any DeepLinkHandler<Route>)` - Inicializar con routing y handler
- `handle(url: URL) async` - Manejar una URL de deep link a través del flujo completo

## Ejemplos de Uso

### Definición Básica de Ruta

```swift
enum AppRoute: DeepLinkRoute {
    case profile(userId: String)
    case product(productId: String)
    
    var id: String {
        switch self {
        case .profile(let userId): "profile-\(userId)"
        case .product(let productId): "product-\(productId)"
        }
    }
}
```

### Implementación de Parser Personalizado

```swift
final class ProfileParser: DeepLinkParser {
    typealias Route = AppRoute
    
    func parse(from url: URL) throws -> [AppRoute] {
        let deepLinkURL = try DeepLinkURL(url: url)
        
        switch deepLinkURL.host {
        case "profile":
            guard let userId = deepLinkURL.queryParameters["userId"] else {
                throw DeepLinkError.missingRequiredParameter("userId")
            }
            return [.profile(userId: userId)]
        default:
            throw DeepLinkError.unsupportedHost(deepLinkURL.host)
        }
    }
}
```

### Implementación de Handler Personalizado

```swift
final class AppDeepLinkHandler: DeepLinkHandler {
    typealias Route = AppRoute
    private let navigationService: NavigationService
    
    init(navigationService: NavigationService) {
        self.navigationService = navigationService
    }
    
    func handle(_ route: AppRoute) async throws {
        switch route {
        case .profile(let userId):
            await navigationService.navigateToProfile(userId: userId)
        case .product(let productId):
            await navigationService.navigateToProduct(productId: productId)
        }
    }
}
```

### Configuración Completa

```swift
let parsers: [any DeepLinkParser<AppRoute>] = [
    ProfileParser(),
    ProductParser()
]

let routing = DefaultDeepLinkRouting<AppRoute>(parsers: parsers)
let handler = AppDeepLinkHandler(navigationService: navigationService)
let coordinator = DeepLinkCoordinator(routing: routing, handler: handler)

// Manejar un deep link
await coordinator.handle(url: deepLinkURL)
```

## Sistema de Middleware

La librería proporciona un sistema de middleware poderoso para interceptar y procesar deep links antes de que lleguen a los parsers.

### DeepLinkMiddleware

Protocolo básico de middleware para interceptar URLs:

```swift
public protocol DeepLinkMiddleware: Sendable {
    func intercept(_ url: URL) async throws -> URL?
}
```

### DeepLinkMiddlewareCoordinator

Coordina la ejecución de middleware en secuencia:

```swift
let coordinator = DeepLinkMiddlewareCoordinator()
coordinator.add(AnalyticsMiddleware())
coordinator.add(AuthenticationMiddleware())
coordinator.add(RateLimitMiddleware())

let processedURL = try await coordinator.process(url)
```

### Middleware Comunes

La librería incluye varias implementaciones de middleware integradas:

#### LoggingMiddleware
Registra todos los intentos de deep link para debugging:

```swift
coordinator.add(LoggingMiddleware())
```

#### AnalyticsMiddleware
Rastrea el uso de deep links para analytics:

```swift
let analyticsProvider = CustomAnalyticsProvider()
coordinator.add(AnalyticsMiddleware(analyticsProvider: analyticsProvider))
```

#### RateLimitMiddleware
Previene abuso limitando las solicitudes:

```swift
coordinator.add(RateLimitMiddleware(maxRequests: 100, timeWindow: 60.0))
```

#### AuthenticationMiddleware
Valida autenticación para rutas protegidas:

```swift
let authProvider = CustomAuthenticationProvider()
coordinator.add(AuthenticationMiddleware(
    authProvider: authProvider,
    protectedHosts: ["profile", "settings"]
))
```

#### SecurityMiddleware
Valida URLs contra políticas de seguridad:

```swift
let securityMiddleware = SecurityMiddleware(
    allowedSchemes: ["myapp"],
    allowedHosts: ["profile", "product"],
    blockedPatterns: [maliciousPattern]
)
coordinator.add(securityMiddleware)
```

#### URLTransformationMiddleware
Transforma URLs antes del procesamiento:

```swift
coordinator.add(URLTransformationMiddleware(
    transformer: URLNormalizationTransformer()
))
```

### Middleware Avanzado

Para más control sobre el flujo de procesamiento:

```swift
public protocol AdvancedDeepLinkMiddleware: Sendable {
    func intercept(_ url: URL) async -> MiddlewareResult
}

public enum MiddlewareResult {
    case `continue`(URL)
    case transform(URL)
    case error(Error)
    case handled
}
```

### Integración con DeepLinkCoordinator

El `DeepLinkCoordinator` incluye automáticamente soporte para middleware:

```swift
let coordinator = DeepLinkCoordinator(routing: routing, handler: handler)

// Agregar middleware
coordinator.add(AnalyticsMiddleware())
coordinator.add(AuthenticationMiddleware())

// Manejar deep links (middleware se ejecuta automáticamente)
await coordinator.handle(url: deepLinkURL)
```

## Manejo de Errores

La librería proporciona manejo de errores comprensivo a través del enum `DeepLinkError`:

```swift
do {
    await coordinator.handle(url: url)
} catch let error as DeepLinkError {
    switch error {
    case .invalidURL(let url):
        print("URL inválida: \(url)")
    case .unsupportedHost(let host):
        print("Host no compatible: \(host)")
    case .routeNotFound(let host):
        print("No se encontró parser para el host: \(host)")
    case .missingRequiredParameter(let parameter):
        print("Parámetro requerido faltante: \(parameter)")
    case .rateLimitExceeded(let count, let interval):
        print("Límite de velocidad excedido: \(count) solicitudes en \(interval) segundos")
    case .securityViolation(let reason):
        print("Violación de seguridad: \(reason)")
    case .unauthorizedAccess(let resource):
        print("Acceso no autorizado a: \(resource)")
    case .blockedURL(let url):
        print("URL bloqueada: \(url)")
    }
} catch {
    print("Error inesperado: \(error)")
}
```

## Seguridad de Hilos

Todos los componentes están diseñados para ser seguros en hilos:

- `DeepLinkCoordinator` está marcado como `@unchecked Sendable`
- Todas las operaciones se realizan de forma asíncrona
- No hay estado mutable compartido entre componentes

## Consideraciones de Rendimiento

- Los parsers se intentan en secuencia hasta que uno tenga éxito
- Los parsers fallidos se registran pero no detienen el proceso
- La validación de URL ocurre antes de los intentos de parsing
- Considera cachear resultados parseados para URLs accedidas frecuentemente

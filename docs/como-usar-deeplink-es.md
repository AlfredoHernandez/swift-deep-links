# Cómo Usar DeepLink

Una guía completa para implementar deep links en tu app iOS usando la librería DeepLink.

## Tabla de Contenidos

1. [Instalación](#instalación)
2. [Configuración Básica](#configuración-básica)
3. [Crear Rutas](#crear-rutas)
4. [Implementar Parsers](#implementar-parsers)
5. [Crear Handlers](#crear-handlers)
6. [Configurar Routing](#configurar-routing)
7. [Integrar con SwiftUI](#integrar-con-swiftui)
8. [Uso Avanzado](#uso-avanzado)
9. [Mejores Prácticas](#mejores-prácticas)
10. [Solución de Problemas](#solución-de-problemas)

## Instalación

### Swift Package Manager

Agrega el paquete DeepLink a tu proyecto:

```swift
dependencies: [
    .package(url: "https://github.com/AlfredoHdz/swift-deep-link.git", from: "1.0.0")
]
```

Luego agrégalo a tu target:

```swift
.target(
    name: "TuApp",
    dependencies: ["DeepLink"]
)
```

## Configuración Básica

### 1. Define Tus Rutas

Primero, crea un enum que conforme al protocolo `DeepLinkRoute`:

```swift
import DeepLinks

enum AppRoute: DeepLinkRoute {
    case profile(userId: String)
    case product(productId: String, category: String)
    case settings(section: String)
    
    var id: String {
        switch self {
        case .profile(let userId):
            return "profile-\(userId)"
        case .product(let productId, let category):
            return "product-\(productId)-\(category)"
        case .settings(let section):
            return "settings-\(section)"
        }
    }
}
```

### 2. Crear Modelos de Parámetros

Define modelos para los parámetros de tu URL:

```swift
struct ProfileParameters: Decodable {
    let userId: String
    let name: String?
}

struct ProductParameters: Decodable {
    let productId: String
    let category: String
}

struct SettingsParameters: Decodable {
    let section: String
}
```

## Implementar Parsers

### 1. Crear Parsers Individuales

```swift
import DeepLinks

final class ProfileParser: DeepLinkParser {
    typealias Route = AppRoute
    private let parameterParser: any QueryParameterParser
    
    init(parameterParser: any QueryParameterParser = JSONQueryParameterParser()) {
        self.parameterParser = parameterParser
    }
    
    func parse(from url: URL) throws -> [AppRoute] {
        let deepLinkURL = try DeepLinkURL(url: url)
        
        switch deepLinkURL.host {
        case "profile":
            return try parseProfileData(from: deepLinkURL)
        default:
            throw DeepLinkError.unsupportedHost(deepLinkURL.host)
        }
    }
    
    private func parseProfileData(from url: DeepLinkURL) throws -> [AppRoute] {
        let data = try parameterParser.parse(ProfileParameters.self, from: url.queryParameters)
        return [.profile(userId: data.userId)]
    }
}
```

### 2. Crear Parsers Adicionales

```swift
final class ProductParser: DeepLinkParser {
    typealias Route = AppRoute
    private let parameterParser: any QueryParameterParser
    
    init(parameterParser: any QueryParameterParser = JSONQueryParameterParser()) {
        self.parameterParser = parameterParser
    }
    
    func parse(from url: URL) throws -> [AppRoute] {
        let deepLinkURL = try DeepLinkURL(url: url)
        
        switch deepLinkURL.host {
        case "product":
            return try parseProductData(from: deepLinkURL)
        default:
            throw DeepLinkError.unsupportedHost(deepLinkURL.host)
        }
    }
    
    private func parseProductData(from url: DeepLinkURL) throws -> [AppRoute] {
        let data = try parameterParser.parse(ProductParameters.self, from: url.queryParameters)
        return [.product(productId: data.productId, category: data.category)]
    }
}
```

## Crear Handlers

### 1. Implementar Handlers de Rutas

```swift
import DeepLinks

final class AppDeepLinkHandler: DeepLinkHandler {
    typealias Route = AppRoute
    private let navigationCoordinator: NavigationCoordinator
    
    init(navigationCoordinator: NavigationCoordinator) {
        self.navigationCoordinator = navigationCoordinator
    }
    
    func handle(_ route: AppRoute) async throws {
        switch route {
        case .profile(let userId):
            await navigationCoordinator.navigateToProfile(userId: userId)
            
        case .product(let productId, let category):
            await navigationCoordinator.navigateToProduct(productId: productId, category: category)
            
        case .settings(let section):
            await navigationCoordinator.navigateToSettings(section: section)
        }
    }
}
```

### 2. Coordinador de Navegación

```swift
@MainActor
final class NavigationCoordinator: ObservableObject {
    @Published var currentRoute: AppRoute?
    
    func navigateToProfile(userId: String) async {
        currentRoute = .profile(userId: userId)
    }
    
    func navigateToProduct(productId: String, category: String) async {
        currentRoute = .product(productId: productId, category: category)
    }
    
    func navigateToSettings(section: String) async {
        currentRoute = .settings(section: section)
    }
}
```

## Configurar Routing

### 1. Configurar Deep Link Routing

```swift
import DeepLinks

final class DeepLinkManager {
    private let routing: any DeepLinkRouting<AppRoute>
    private let handler: any DeepLinkHandler<AppRoute>
    private let coordinator: DeepLinkCoordinator<AppRoute>
    
    init(navigationCoordinator: NavigationCoordinator) {
        // Crear parsers
        let parsers: [any DeepLinkParser<AppRoute>] = [
            ProfileParser(),
            ProductParser(),
            SettingsParser()
        ]
        
        // Crear routing
        self.routing = DefaultDeepLinkRouting<AppRoute>(parsers: parsers)
        
        // Crear handler
        self.handler = AppDeepLinkHandler(navigationCoordinator: navigationCoordinator)
        
        // Crear coordinator
        self.coordinator = DeepLinkCoordinator(routing: routing, handler: handler)
    }
    
    func handle(url: URL) async {
        await coordinator.handle(url: url)
    }
}
```

## Integrar con SwiftUI

### 1. Integración en la App

```swift
import SwiftUI
import DeepLinks

@main
struct MiApp: App {
    @StateObject private var navigationCoordinator = NavigationCoordinator()
    @State private var deepLinkManager: DeepLinkManager?
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(navigationCoordinator)
                .onAppear {
                    deepLinkManager = DeepLinkManager(navigationCoordinator: navigationCoordinator)
                }
                .onOpenURL { url in
                    Task {
                        await deepLinkManager?.handle(url: url)
                    }
                }
        }
    }
}
```

### 2. Vista de Contenido con Navegación

```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Bienvenido a Mi App")
                
                Button("Ir al Perfil") {
                    Task {
                        await navigationCoordinator.navigateToProfile(userId: "123")
                    }
                }
                
                Button("Ir al Producto") {
                    Task {
                        await navigationCoordinator.navigateToProduct(productId: "PROD-001", category: "Electrónicos")
                    }
                }
            }
            .navigationDestination(item: $navigationCoordinator.currentRoute) { route in
                switch route {
                case .profile(let userId):
                    ProfileView(userId: userId)
                case .product(let productId, let category):
                    ProductView(productId: productId, category: category)
                case .settings(let section):
                    SettingsView(section: section)
                }
            }
        }
    }
}
```

## Uso Avanzado

### 1. Parser de Parámetros Personalizado

```swift
final class CustomParameterParser: QueryParameterParser {
    func parse<T: Decodable>(_ type: T.Type, from parameters: [String: String]) throws -> T {
        // Lógica de parsing personalizada
        let data = try JSONSerialization.data(withJSONObject: parameters)
        return try JSONDecoder().decode(type, from: data)
    }
}
```

### 2. Manejo de Múltiples Rutas

```swift
final class MultiRouteParser: DeepLinkParser {
    typealias Route = AppRoute
    
    func parse(from url: URL) throws -> [AppRoute] {
        let deepLinkURL = try DeepLinkURL(url: url)
        
        switch deepLinkURL.host {
        case "dashboard":
            // Retornar múltiples rutas para dashboard
            return [
                .profile(userId: "current-user"),
                .settings(section: "preferences")
            ]
        default:
            throw DeepLinkError.unsupportedHost(deepLinkURL.host)
        }
    }
}
```

### 3. Manejo de Errores

```swift
final class ErrorHandlingParser: DeepLinkParser {
    typealias Route = AppRoute
    
    func parse(from url: URL) throws -> [AppRoute] {
        do {
            let deepLinkURL = try DeepLinkURL(url: url)
            // Lógica de parsing
            return [.profile(userId: "default")]
        } catch {
            // Registrar error y retornar ruta por defecto
            print("Error parsing URL: \(error)")
            return [.profile(userId: "default")]
        }
    }
}
```

## Mejores Prácticas

### 1. Estructura de URL

Usa estructuras de URL consistentes:

```
miapp://profile?userId=123&name=Juan
miapp://product?productId=PROD-001&category=Electrónicos
miapp://settings?section=account
```

### 2. Manejo de Errores

Siempre maneja los errores de parsing de manera elegante:

```swift
func handle(url: URL) async {
    do {
        await coordinator.handle(url: url)
    } catch {
        // Manejar error apropiadamente
        print("Error de deep link: \(error)")
    }
}
```

### 3. Testing

Prueba tu implementación de deep links:

```swift
func testProfileDeepLink() async throws {
    let url = URL(string: "miapp://profile?userId=123")!
    let result = try await parser.parse(from: url)
    
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result.first, .profile(userId: "123"))
}
```

### 4. Rendimiento

- Usa inicialización lazy para parsers
- Cachea resultados parseados cuando sea apropiado
- Evita bloquear el hilo principal

## Solución de Problemas

### Problemas Comunes

1. **URL no está siendo manejada**
   - Verifica el registro del esquema de URL en Info.plist
   - Confirma que el parser coincida con el host
   - Asegúrate del manejo apropiado de errores

2. **Parámetros no se parsean correctamente**
   - Revisa la estructura del modelo de parámetros
   - Verifica la codificación de URL
   - Prueba con diferentes combinaciones de parámetros

3. **Navegación no funciona**
   - Asegúrate de que el handler esté implementado correctamente
   - Revisa la configuración del coordinador de navegación
   - Verifica la estructura de navegación de SwiftUI

### Consejos de Debug

1. Habilita logging en tus parsers
2. Prueba URLs en el simulador
3. Usa la app de muestra como referencia
4. Revisa la suite de tests para ejemplos

## URLs de Ejemplo

Prueba tu implementación con estas URLs:

```
miapp://profile?userId=123&name=Juan%20Pérez
miapp://product?productId=PROD-001&category=Electrónicos
miapp://settings?section=account
miapp://dashboard
```

## Próximos Pasos

1. Explora la [App de Muestra](../DeepLinkSample/) para una implementación completa
2. Consulta la [Referencia de API](./referencia-api-es.md) para documentación detallada
3. Revisa los [Tests](../Tests/) para ejemplos de uso
4. Contribuye al proyecto en [GitHub](https://github.com/AlfredoHdz/swift-deep-link)

//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

// MARK: - Convenience Type Aliases

/// A convenience type alias for `DeepLinkCoordinator<R.Route>` where `R` is a `DeepLinkRoute`.
///
/// This type alias reduces verbosity when working with coordinators for specific route types.
///
/// ## Usage
///
/// ```swift
/// // Before
/// let coordinator: DeepLinkCoordinator<AppRoute> = ...
///
/// // After
/// let coordinator: CoordinatorOf<AppRoute> = ...
/// ```
public typealias CoordinatorOf<Route: DeepLinkRoute> = DeepLinkCoordinator<Route>

/// A convenience type alias for `any DeepLinkParser<Route>`.
///
/// This type alias provides a more ergonomic way to reference existential parser types.
///
/// ## Usage
///
/// ```swift
/// // Before
/// let parser: any DeepLinkParser<AppRoute> = ...
///
/// // After
/// let parser: ParserOf<AppRoute> = ...
/// ```
public typealias ParserOf<Route: DeepLinkRoute> = any DeepLinkParser<Route>

/// A convenience type alias for `any DeepLinkHandler<Route>`.
///
/// This type alias provides a more ergonomic way to reference existential handler types.
///
/// ## Usage
///
/// ```swift
/// // Before
/// let handler: any DeepLinkHandler<AppRoute> = ...
///
/// // After
/// let handler: HandlerOf<AppRoute> = ...
/// ```
public typealias HandlerOf<Route: DeepLinkRoute> = any DeepLinkHandler<Route>

/// A convenience type alias for `any DeepLinkRouting<Route>`.
///
/// This type alias provides a more ergonomic way to reference existential routing types.
///
/// ## Usage
///
/// ```swift
/// // Before
/// let routing: any DeepLinkRouting<AppRoute> = ...
///
/// // After
/// let routing: RoutingOf<AppRoute> = ...
/// ```
public typealias RoutingOf<Route: DeepLinkRoute> = any DeepLinkRouting<Route>

/// A convenience type alias for `DeepLinkResult<Route>`.
///
/// This type alias provides consistency with other `*Of` type aliases in the API.
///
/// ## Usage
///
/// ```swift
/// // Before
/// func handleResult(_ result: DeepLinkResult<AppRoute>) { ... }
///
/// // After
/// func handleResult(_ result: ResultOf<AppRoute>) { ... }
/// ```
public typealias ResultOf<Route: DeepLinkRoute> = DeepLinkResult<Route>

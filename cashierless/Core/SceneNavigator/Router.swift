//
//  Router.swift
//  cashierless
//
//  Created by Shafa Tiara on 18/05/26.
//
import SwiftUI
import Combine

// MARK: - AppRoute

enum AppRoute: Hashable {
    case detection
    case scanBarcode
    case checkout
}

// MARK: - Router

final class Router: ObservableObject {
    @Published var path = NavigationPath()

    func navigate(to route: AppRoute) { path.append(route) }
    func navigateBack()               { path.removeLast() }
    func navigateToRoot()             { path.removeLast(path.count) }
}

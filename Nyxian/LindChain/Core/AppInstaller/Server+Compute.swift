//
//  Server+Compute.swift
//  feather
//
//  Created by samara on 22.08.2024.
//  Copyright © 2024 Lakr Aream. All Rights Reserved.
//  ORIGINALLY LICENSED UNDER GPL-3.0, MODIFIED FOR USE FOR FEATHER
//

import Foundation
import UIKit

extension Installer {
    
    var plistEndpoint: URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = Self.sni
        comps.path = "/\(id).plist"
        comps.port = port
        return comps.url!
    }

    var payloadEndpoint: URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = Self.sni
        comps.path = "/\(id).ipa"
        comps.port = port
        return comps.url!
    }

    var iTunesLink: URL {
        var comps = URLComponents()
        comps.scheme = "itms-services"
        comps.path = "/"
        comps.queryItems = [
            URLQueryItem(name: "action", value: "download-manifest"),
            URLQueryItem(name: "url", value: plistEndpoint.absoluteString),
        ]
        comps.port = port
        return comps.url!
    }

    var displayImageSmallEndpoint: URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = Self.sni
        comps.path = "/app57x57.png"
        comps.port = port
        return comps.url!
    }

    var displayImageSmallData: Data {
        createImage(self.image, 57) ?? createWhite(57)
    }

    var displayImageLargeEndpoint: URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = Self.sni
        comps.path = "/app512x512.png"
        comps.port = port
        return comps.url!
    }

    var displayImageLargeData: Data {
        createImage(self.image, 512) ?? createWhite(512)
    }
    
    func createWhite(_ r: CGFloat) -> Data {
        let renderer = UIGraphicsImageRenderer(size: .init(width: r, height: r))
        let image = renderer.image { ctx in
            ctx.fill(.init(x: 0, y: 0, width: r, height: r))
        }
        return image.pngData()!
    }
    
    func createImage(_ image: UIImage?,
                     _ r: CGFloat) -> Data? {
        
        if let image = image {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: r, height: r))
            let resizedImage = renderer.image { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: r, height: r))
            }
            
            return resizedImage.pngData()
        }
        
        return nil
    }

    var installManifest: [String: Any] {
        [
            "items": [
                [
                    "assets": [
                        [
                            "kind": "software-package",
                            "url": payloadEndpoint.absoluteString,
                        ],
                        [
                            "kind": "display-image",
                            "url": displayImageSmallEndpoint.absoluteString,
                        ],
                        [
                            "kind": "full-size-image",
                            "url": displayImageLargeEndpoint.absoluteString,
                        ],
                    ],
                    "metadata": [
                        "bundle-identifier": metadata.id,
                        "bundle-version": metadata.version,
                        "kind": "software",
                        "title": metadata.name,
                    ],
                ],
            ],
        ]
    }

    var installManifestData: Data {
        (try? PropertyListSerialization.data(
            fromPropertyList: installManifest,
            format: .xml,
            options: .zero
        )) ?? .init()
    }
}

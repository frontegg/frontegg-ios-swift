//
//  Extensions.swift
//
//

import Foundation
import UIKit


extension UIColor{
    static var commonElementBGColor : UIColor = UIColor(red: 235/255, green: 234/255, blue: 254/255, alpha: 1)
    static var themeBGColor : UIColor = UIColor(red: 240/255, green: 243/255, blue: 245/255, alpha: 1)
    static var themePurpleColor : UIColor = UIColor(red: 90/255, green: 83/255, blue: 221/255, alpha: 1)
    static var themeTextGrayColor : UIColor = UIColor(red: 153/255, green: 142/255, blue: 142/255, alpha: 1)
}

/// An extension that provides common functionality for UIView.
extension UIView {
    /// Adds a shadow to the view.
    func dropShadow(scale: Bool = true) {
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.5
        layer.shadowOffset = CGSize(width: -1, height: 1)
        layer.shadowRadius = 1
        
        layer.shadowPath = UIBezierPath(rect: bounds).cgPath
        layer.shouldRasterize = true
        layer.rasterizationScale = scale ? UIScreen.main.scale : 1
    }
    
    /// Adds a shadow to the view with a specific color, opacity, offset, and radius.
    func dropShadow(color: UIColor, opacity: Float = 0.5, offSet: CGSize, radius: CGFloat = 1, scale: Bool = true) {
        layer.masksToBounds = false
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = opacity
        layer.shadowOffset = offSet
        layer.shadowRadius = radius
        
        layer.shadowPath = UIBezierPath(rect: self.bounds).cgPath
        layer.shouldRasterize = true
        layer.rasterizationScale = scale ? UIScreen.main.scale : 1
    }
}
extension UIImage {
    /// Converts the image to a base64 string.
    var base64: String? {
        self.jpegData(compressionQuality: 1)?.base64EncodedString()
    }
}

extension String {
    /// Decodes the string from a base64 string to a regular string.
    var decodeEmoji: String{
        let data = self.data(using: String.Encoding.utf8);
        let decodedStr = NSString(data: data!, encoding: String.Encoding.nonLossyASCII.rawValue)
        if let str = decodedStr{
            return str as String
        }
        return self
    }
    
    /// Encodes the string to a base64 string.
    var encodeEmoji: String{
        if let encodeStr = NSString(cString: self.cString(using: .nonLossyASCII)!, encoding: String.Encoding.utf8.rawValue){
            return encodeStr as String
        }
        return self
    }
}


/// A variable that returns the scene delegate for the current application.
var sceneDelegate: SceneDelegate? {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let delegate = windowScene.delegate as? SceneDelegate else { return nil }
    return delegate
}

/// An extension that provides common functionality for UIViewController.
extension UIViewController {
    /// A variable that returns the window for the current application.
    var window: UIWindow? {
        if #available(iOS 13, *) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let delegate = windowScene.delegate as? SceneDelegate, let window = delegate.window else { return nil }
            return window
        }
        
        guard let delegate = UIApplication.shared.delegate as? AppDelegate, let window = delegate.window else { return nil }
        return window
    }
}

/// An extension that provides common functionality for URL.
extension URL {
    /// A variable that returns the components for the current URL.
    var components: URLComponents? {
        return URLComponents(url: self, resolvingAgainstBaseURL: false)
    }
}

//
//  Logger.swift
//  
//
//  Created by David Frontegg on 22/01/2023.
//

import Foundation
import Logging


public func getLogger(_ className: String) -> Logger {
    var logger = Logger(label: className)
    logger.logLevel = PlistHelper.getLogLevel()
    return logger
}


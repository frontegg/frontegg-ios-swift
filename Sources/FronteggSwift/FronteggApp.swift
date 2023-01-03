//
//  FronteggApp.swift
//  
//
//  Created by David Frontegg on 22/12/2022.
//

import Foundation
//import UserNotifications
import UIKit
//import CloudKit

public class FronteggApp {
    
    public static let shared = FronteggApp()
    
    public let auth: FronteggAuth
    public let baseUrl: String
    public let clientId: String
    let api: Api
    let credentialManager: CredentialManager
    
    init() {
        guard let data = try? PlistHelper.fronteggConfig() else {
            exit(1)
        }
            
        
        self.baseUrl = data.baseUrl
        self.clientId = data.clientId
        self.credentialManager = CredentialManager(serviceKey: data.keychainService)
        self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId, credentialManager: self.credentialManager)
        
        self.auth = FronteggAuth(
            baseUrl: self.baseUrl,
            clientId: self.clientId,
            api: self.api,
            credentialManager: self.credentialManager
        )
    }
 
    public func didFinishLaunchingWithOptions(){
        print("Frontegg baseURL: \(self.baseUrl)")
        
        
        
        /** using  Notification Center for private keys */
        
//        let center = UNUserNotificationCenter.current()
//        center.requestAuthorization(options:[.provisional]) { (granted, error) in
//            print("NOTI: error \(error)")
//            print("NOTI: granted \(granted)")
//
//
//            UNUserNotificationCenter.current().getNotificationSettings { settings in
////                 guard settings.authorizationStatus == .authorized else { return }
//
//                 DispatchQueue.main.async {
//                  UIApplication.shared.registerForRemoteNotifications()
//                 }
//
//               }
//        }
        
        
        /** using  CloudKit for private keys */

        //        let database = CKContainer.default().publicCloudDatabase
//        let predicate = NSPredicate(value: true)
//        let query = CKQuery(recordType: "Frontegg", predicate: predicate)
//
//        let operation = CKQueryOperation(query: query)
//        operation.resultsLimit = 1
//
//        operation.recordFetchedBlock = { record in
//            print("CKit record: \(record["baseUrl"] as! String)")
//        }
//
//        operation.queryCompletionBlock = { (cursor, error) in
//            print("CKit cursor: \(cursor)")
//            print("CKit error: \(error)")
//        }
//        database.add(operation)
    }
    
    
}

//
//  NetworkManager.swift
//  RocketLaunch
//
//  Created by 3DaysOfSwift.com 06/12/2023.
//

import Foundation

struct NetworkManager {
    
    func fetchData(from url: URL, completion: @escaping (Data?) -> ()) {
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            completion(data)
        }

        task.resume()
    }
    
}

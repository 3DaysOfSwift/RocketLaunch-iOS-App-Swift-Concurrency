//
//  NetworkManager.swift
//  RocketLaunch
//
//  Created by 3DaysOfSwift.com 06/12/2023.
//

import Foundation

struct NetworkManager {
    let session: URLSession

    init(session: URLSession) {
        self.session = session
    }
    
    func fetchData(from url: URL, completion: @escaping (Data?) -> ()) {
        let task = session.dataTask(with: url) { data, response, error in
            completion(data)
        }

        task.resume()
    }
    
}

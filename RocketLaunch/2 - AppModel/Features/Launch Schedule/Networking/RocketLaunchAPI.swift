//
//  RocketLaunchSchedule.swift
//  RocketLaunch
//
//  Created by 3DaysOfSwift.com 06/12/2023.
//

import Foundation

enum RocketLaunchAPIError: Error {
    case decodingFailure(Error)
    case networkingError
}

struct RocketLaunchAPI: LaunchRepository {
    let apiWebAddress: String = "https://fdo.rocketlaunch.live/json/launches/next/5"
    let networkManager: NetworkManager
    
    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }
    
    func fetchUpcomingLaunches(completion: @escaping (Result<[RocketLaunch], RocketLaunchAPIError>) -> Void) {
        guard let apiEndPoint = URL(string: apiWebAddress) else {
            // TODO: handle errors
            return
        }
        
        networkManager.fetchData(from: apiEndPoint) { data in
            if let data = data {
                do
                {
                    let rocketLaunches = try JSONDecoder().decode(SearchResultsPage.self, from: data)
                    completion(.success(rocketLaunches.result))
                }
                catch (let error) {
                    completion(.failure(RocketLaunchAPIError.decodingFailure(error)))
                }
            } else {
                completion(.failure(RocketLaunchAPIError.networkingError))
            }
        }
    }
}

//
//  GOTHousesService.swift
//  GameOfThronesHOUSES
//
//  Created by Simu Voicu-Mircea on 18.06.2023.
//

import Foundation

class GOTHousesService {
    func getHouses(page: Int = 1,
                   pageSize: Int = 5,
                   callBack: @escaping ([GOTHouseModel], Bool) -> Void) {

        var components = URLComponents()
        components.scheme = "https"
        components.host = "anapioficeandfire.com"
        components.path = "/api/houses"

        components.queryItems = [
            URLQueryItem(name: "pageSize", value: "\(pageSize)"),
            URLQueryItem(name: "page", value: "\(page)")
        ]

        if let url = URL(string: components.string ?? "") {
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                debugPrint(response ?? "")
                if let data = data {
                    if let houses = try? JSONDecoder().decode([GOTHouseModel].self, from: data) {
                        callBack(houses, false)
                    } else {
                        callBack([], true)
                    }
                } else if let error = error {
                    callBack([], true)
                    print("HTTP Request Failed \(error)")
                }
            }
        }
    }
}

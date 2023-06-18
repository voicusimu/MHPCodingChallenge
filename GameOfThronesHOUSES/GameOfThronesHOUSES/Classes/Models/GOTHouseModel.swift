//
//  GOTHouseModel.swift
//  GameOfThronesHOUSES
//
//  Created by Simu Voicu-Mircea on 18.06.2023.
//

import Foundation

import Foundation

struct GOTHouseModel: Codable {
    let url: String
    let name: String
    let region: String?
    let coatOfArms: String?
    let words: String?
    let titles: [String]
    let seats: [String]
    let currentLord: String
    let heir: String
    let overlord: String
    let founded: String
    let founder: String
    let diedOut: String
    let ancestralWeapons: [String]
    let cadetBranches: [String]
    let swornMembers: [String]
}

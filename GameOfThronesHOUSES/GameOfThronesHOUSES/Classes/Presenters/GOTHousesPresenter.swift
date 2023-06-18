//
//  GOTHousesPresenter.swift
//  GameOfThronesHOUSES
//
//  Created by Simu Voicu-Mircea on 18.06.2023.
//

import Foundation

protocol GOTHousesViewDelegate: NSObjectProtocol {
    func didLoadInitialHouses(houses: [GOTHouseModel], hasError: Bool)
    func didLoadMoreHouses(houses: [GOTHouseModel], hasError: Bool)
}

class GOTHousesPresenter {
    private let housesService: GOTHousesService
    weak private var housesDelegate: GOTHousesViewDelegate?
    var currentPage = 1
    init(housesService: GOTHousesService) {
        self.housesService = housesService
    }

    func setViewDelegate(housesDelegate: GOTHousesViewDelegate?) {
        self.housesDelegate = housesDelegate
    }

    func loadMoreHouses() {
        housesService.getHouses(page: currentPage + 1) { [weak self] (houses, hasError) in
            if houses.count > 0 {
                self?.currentPage+=1
            }
            self?.housesDelegate?.didLoadMoreHouses(houses: houses, hasError: hasError)
        }
    }

    func showInitialHouses() {
        currentPage = 1
        housesService.getHouses(page: currentPage) { [weak self] (houses, hasError) in
            self?.housesDelegate?.didLoadInitialHouses(houses: houses, hasError: hasError)
        }
    }
}

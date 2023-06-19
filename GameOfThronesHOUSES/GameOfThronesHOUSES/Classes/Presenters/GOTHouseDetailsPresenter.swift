//
//  GOTHouseDetailsPresenter.swift
//  GameOfThronesHOUSES
//
//  Created by Simu Voicu-Mircea on 18.06.2023.
//

import Foundation

protocol GOTHouseDetailsDelegate: NSObjectProtocol {
    func showDetails(for model: GOTHouseModel)
}

class GOTHouseDetailsPresenter {
    weak private var detailsViewDelegate: GOTHouseDetailsDelegate?
    private var model: GOTHouseModel

    init(houseModel: GOTHouseModel) {
        self.model = houseModel
    }

    func setViewDelegate(detailsViewDelegate: GOTHouseDetailsDelegate?) {
        self.detailsViewDelegate = detailsViewDelegate
    }

    func showDetails() {
        detailsViewDelegate?.showDetails(for: model)
    }
}

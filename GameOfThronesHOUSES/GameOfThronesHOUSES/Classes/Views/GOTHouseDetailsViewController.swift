//
//  GOTHouseDetailsViewController.swift
//  GameOfThronesHOUSES
//
//  Created by Simu Voicu-Mircea on 18.06.2023.
//

import UIKit

class GOTHouseDetailsViewController: UIViewController {
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var regionLabel: UILabel!
    @IBOutlet weak var coatOfArmsLabel: UILabel!
    @IBOutlet weak var wordsLabel: UILabel!
    @IBOutlet weak var titlesLabel: UILabel!
    @IBOutlet weak var seatsLabel: UILabel!
    @IBOutlet weak var currentLordLabel: UILabel!
    @IBOutlet weak var heirLabel: UILabel!
    @IBOutlet weak var overlordLabel: UILabel!
    @IBOutlet weak var foundedLabel: UILabel!
    @IBOutlet weak var founderLabel: UILabel!
    @IBOutlet weak var diedoutLabel: UILabel!
    @IBOutlet weak var weaponsLabel: UILabel!
    @IBOutlet weak var cadetLabel: UILabel!
    @IBOutlet weak var swornMembersLabel: UILabel!
    var detailsPresenter: GOTHouseDetailsPresenter?

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let presenter = detailsPresenter else {
            return
        }
        detailsPresenter?.setViewDelegate(detailsViewDelegate: self)
        presenter.showDetails()
    }
}

extension GOTHouseDetailsViewController: GOTHouseDetailsDelegate {
    func showDetails(for model: GOTHouseModel) {
        self.titleLabel.text = model.name
        self.regionLabel.text = "Region: " + (model.region ?? "")
        self.coatOfArmsLabel.text = "Region: " + (model.coatOfArms ?? "")
        self.wordsLabel.text = "Region: " + (model.words ?? "")
        var titles = "Titles: "
        for (index, title) in model.titles.enumerated() {
            let separator = index < model.titles.count - 1 ? ", " : ""
            titles += title + separator
        }
        self.titlesLabel.text = titles

        var seats = "Seats: "
        for (index, seat) in model.seats.enumerated() {
            let separator = index < model.seats.count - 1 ? ", " : ""
            seats += seat + separator
        }
        self.seatsLabel.text = seats

        self.currentLordLabel.text = "Current lord: " + model.currentLord
        self.heirLabel.text = "Heir: " + model.heir
        self.overlordLabel.text = "Overlord: " + model.overlord
        self.foundedLabel.text = "Founded: " + model.founded
        self.founderLabel.text = "Founder: " + model.founder
        self.diedoutLabel.text = "Died out: " + model.diedOut

        self.weaponsLabel.text = "Ancestral weapons: " + "\(model.ancestralWeapons.count)"
        self.cadetLabel.text = "Cadet branches: " + "\(model.cadetBranches.count)"
        self.swornMembersLabel.text = "Sworn members: " + "\(model.swornMembers.count)"
    }
}

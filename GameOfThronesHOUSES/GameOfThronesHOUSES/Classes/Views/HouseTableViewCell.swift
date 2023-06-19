//
//  HouseTableViewCell.swift
//  GameOfThronesHOUSES
//
//  Created by Simu Voicu-Mircea on 19.06.2023.
//

import UIKit

class HouseTableViewCell: UITableViewCell {
    @IBOutlet weak var houseThumbnail: UIImageView!
    @IBOutlet weak var houseNameLabel: UILabel!
    @IBOutlet weak var houseRegionLabel: UILabel!

    private var houseModel: GOTHouseModel?

    override func awakeFromNib() {
        super.awakeFromNib()
        self.houseThumbnail.layer.cornerRadius = self.houseThumbnail.frame.size.height / 2
    }

    func setupWithModel(model: GOTHouseModel) {
        houseModel = model
        houseNameLabel.text = model.name
        houseRegionLabel.text = model.region

        // thumbnail
    }
}


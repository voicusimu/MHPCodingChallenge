//
//  UITableView+Extension.swift
//  GameOfThronesHOUSES
//
//  Created by Simu Voicu-Mircea on 19.06.2023.
//

import UIKit

extension UITableView {
    func indicatorView() -> UIActivityIndicatorView {
        var activityIndicatorView = UIActivityIndicatorView()
        activityIndicatorView.hidesWhenStopped = true
        if self.tableFooterView == nil {
            let indicatorFrame = CGRect(x: 0, y: 0, width: self.bounds.width, height: 40)
            activityIndicatorView = UIActivityIndicatorView(frame: indicatorFrame)
            activityIndicatorView.isHidden = false
            activityIndicatorView.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
            activityIndicatorView.isHidden = true
            self.tableFooterView = activityIndicatorView
            return activityIndicatorView
        } else {
            return activityIndicatorView
        }
    }

    func showLoadingMoreIndicator(_ indexPath: IndexPath, closure: @escaping (() -> Void)) {
        indicatorView().startAnimating()
        if let lastVisibleIndexPath = self.indexPathsForVisibleRows?.last {
            if indexPath == lastVisibleIndexPath && indexPath.row == self.numberOfRows(inSection: 0) - 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    closure()
                }
            }
        }
        indicatorView().isHidden = false
    }

    func hideLoadingMoreIndicator() {
        indicatorView().stopAnimating()
        tableFooterView = nil
    }
}


//
//  GOTHousesViewController.swift
//  GameOfThronesHOUSES
//
//  Created by Simu Voicu-Mircea on 18.06.2023.
//

import UIKit

enum StatusType {
    case Loading
    case NoData
    case HasData
    case LoadingMore
    case Error
}

class GOTHousesViewController: UIViewController {
    //MARK: Properties
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var statusLabel: UILabel!

    private let housesPresenter = GOTHousesPresenter(housesService: GOTHousesService())
    var houses: [GOTHouseModel] = []
    var filteredHouses: [GOTHouseModel] = []
    var status: StatusType = .Loading
    let searchController = UISearchController(searchResultsController: nil)

    var isSearchBarEmpty: Bool {
      return searchController.searchBar.text?.isEmpty ?? true
    }

    var isFiltering: Bool {
      return searchController.isActive && !isSearchBarEmpty
    }

    var isInternetAvailable: Bool {
        return true
    }

    //MARK: Life cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.delegate = self
        tableView.dataSource = self
        housesPresenter.setViewDelegate(housesDelegate: self)
        setupStatus(status: .Loading)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search Houses"
        navigationItem.searchController = searchController
        housesPresenter.showInitialHouses()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }
}

//MARK: Delegates

extension GOTHousesViewController: GOTHousesViewDelegate, UITableViewDelegate, UITableViewDataSource, UIScrollViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var datasource: [GOTHouseModel]
        if isFiltering {
            datasource = filteredHouses
        } else {
            datasource = houses
        }
        if datasource.count <= 0 {
            setupStatus(status: .NoData)
        }
        return datasource.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "houseCell", for: indexPath) as? HouseTableViewCell {
            let houseModel: GOTHouseModel
            if isFiltering {
                houseModel = filteredHouses[indexPath.row]
            } else {
                houseModel = houses[indexPath.row]
            }
            cell.setupWithModel(model: houseModel)
            return cell
        }

        return UITableViewCell()
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard houses.count > 10 else {
            return
        }
        let lastElement = houses.count - 10
        if  (indexPath.row == lastElement && status != .LoadingMore && !isFiltering) {
            setupStatus(status: .LoadingMore)
            housesPresenter.loadMoreHouses()
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let houseModel: GOTHouseModel
        if isFiltering {
            houseModel = filteredHouses[indexPath.row]
        } else {
            houseModel = houses[indexPath.row]
        }
        let detailsPresenter = GOTHouseDetailsPresenter(houseModel: houseModel)
        self.performSegue(withIdentifier: "showDetails", sender: detailsPresenter)
    }

    func didLoadInitialHouses(houses: [GOTHouseModel], hasError: Bool) {
        self.houses = houses
        if hasError {
            setupStatus(status: .Error)
        } else {
            setupStatus(status: houses.count > 0 ? .HasData : .NoData)
        }
        tableView.reloadData()
    }

    func didLoadMoreHouses(houses: [GOTHouseModel], hasError: Bool) {
        if hasError {
            setupStatus(status: .Error)
        } else {
            self.houses.append(contentsOf: houses)
            setupStatus(status: .HasData)
            tableView.reloadData()
        }
        tableView.hideLoadingMoreIndicator()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if (self.tableView.contentOffset.y >= (self.tableView.contentSize.height - self.tableView.bounds.size.height - 1) &&
            status != .LoadingMore &&
            !isFiltering) {
            setupStatus(status: .LoadingMore)
            housesPresenter.loadMoreHouses()
        }
    }

//    func scrollViewDidScroll(_ scrollView: UIScrollView) {
//        if self.tableView.contentOffset.y <= 0 {
//            self.segmentedControlTopConstraint.constant = 40 - self.tableView.contentOffset.y
//        } else {
//            self.segmentedControlTopConstraint.constant = 40
//        }
//    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let presenter = sender as? GOTHouseDetailsPresenter,
              let detailsViewController = segue.destination as? GOTHouseDetailsViewController else {
            return
        }
        detailsViewController.detailsPresenter = presenter
    }
}

extension GOTHousesViewController: UISearchResultsUpdating {
  func updateSearchResults(for searchController: UISearchController) {
    guard let searchText = searchController.searchBar.text else {
        return
    }
    filterContentForSearchText(searchText)
  }
}

//MARK: Helpers
extension GOTHousesViewController {
    func setupStatus(status: StatusType) {
        self.status = status
        switch status {
        case .Loading:
            activityIndicator.startAnimating()
            statusLabel.isHidden = false
            tableView.isHidden = true
            statusLabel.text = NSLocalizedString("Loading...", comment: "")
        case .NoData:
            activityIndicator.stopAnimating()
            statusLabel.isHidden = false
            tableView.isHidden = true
            statusLabel.text = NSLocalizedString("No data", comment: "")
        case .HasData:
            activityIndicator.stopAnimating()
            statusLabel.isHidden = true
            tableView.isHidden = false
        case .LoadingMore:
            tableView.showLoadingMoreIndicator(IndexPath(row: houses.count, section: 0), closure: {})
            statusLabel.isHidden = true
            tableView.isHidden = false
        case .Error:
            presentOKAlert(title: "Error", message: NSLocalizedString("An error has occured.\nProbably unauthenticated request limit reached", comment: ""))
            activityIndicator.stopAnimating()
            statusLabel.isHidden = true
            tableView.isHidden = false
            break
        }
    }

    func presentOKAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let dismissAction = UIAlertAction(title: "OK", style: .default) {_ in }
        alert.addAction(dismissAction)
        self.present(alert, animated: true)
    }

    func filterContentForSearchText(_ searchText: String) {
        filteredHouses = houses.filter { (repo: GOTHouseModel) -> Bool in
            return (repo.name.lowercased().contains(searchText.lowercased()))
        }
        tableView.reloadData()
    }
}

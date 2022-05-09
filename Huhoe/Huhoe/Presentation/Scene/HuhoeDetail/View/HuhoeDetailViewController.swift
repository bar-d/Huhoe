//
//  HuhoeDetailViewController.swift
//  Huhoe
//
//  Created by 황제하 on 2022/04/23.
//

import UIKit
import RxSwift
import RxCocoa

final class HuhoeDetailViewController: UIViewController {
    
    
    // MARK: - Collection View
    
    private enum Section: String, CaseIterable {
        case today = "오늘"
        case past = "과거"
    }
        
    private typealias DiffableDataSource = UICollectionViewDiffableDataSource<Section, CoinHistoryItem>
    private var dataSource: DiffableDataSource?
    
    private let tempItems: [CoinHistoryItem] = [
        CoinHistoryItem(date: "1", calculatedPrice: 1, rate: 1, profitAndLoss: 1),
        CoinHistoryItem(date: "2", calculatedPrice: 2, rate: 2, profitAndLoss: 2),
        CoinHistoryItem(date: "3", calculatedPrice: 3, rate: 3, profitAndLoss: 3),
        CoinHistoryItem(date: "3", calculatedPrice: 3, rate: 3, profitAndLoss: 4),
        CoinHistoryItem(date: "3", calculatedPrice: 3, rate: 3, profitAndLoss: 5),
        CoinHistoryItem(date: "3", calculatedPrice: 3, rate: 3, profitAndLoss: 6),
        CoinHistoryItem(date: "3", calculatedPrice: 3, rate: 3, profitAndLoss: 7)
    ]
    
    // MARK: - IBOutlet
    
    @IBOutlet private weak var currentPriceLabel: UILabel!
    @IBOutlet private weak var dateChangeButton: UIButton!
    @IBOutlet private weak var moneyTextField: UITextField!
    @IBOutlet private weak var pastPriceLabel: UILabel!
    @IBOutlet private weak var pastQuantityLabel: UILabel!
    @IBOutlet private weak var coinHistoryCollectionView: UICollectionView!
    @IBOutlet private weak var chartScrollView: ChartScrollView!
    @IBOutlet private weak var chartImageView: ChartImageView!
    
    @IBOutlet private weak var chartOldDateLabel: UILabel!
    @IBOutlet private weak var chartLatestDateLabel: UILabel!
    // MARK: - ViewModel
    var viewModel: HuhoeDetailViewModel?
    private let disposeBag = DisposeBag()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureBackButton()
        configureLabel()
        configureDateChangeButton()
        configureCollectionView()
        configureChartView()
        
        bindViewModel()
        bindTapGesture()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.isNavigationBarHidden = false
    }
}

// MARK: - View Model Methods

extension HuhoeDetailViewController {
    
    // MARK: - Bind ViewModel
    
    private func bindViewModel() {
        
        // MARK: - Input
        
        moneyTextField.text = viewModel?.selectedCoinInformation.coinInvestmentMoney
        currentPriceLabel.text = viewModel?.selectedCoinInformation.coinCurrentPrice
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy.MM.dd"
        dateChangeButton.setTitle(viewModel?.selectedCoinInformation.coinInvestmentDate ?? "", for: .normal)
        let textRelay = BehaviorRelay<String>(value: dateChangeButton.titleLabel?.text ?? "")
        
        dateChangeButton.rx.tap
            .subscribe(onNext: { [weak self] in
                let selectedDate = dateFormatter.date(from: textRelay.value)
                
                let alert = UIAlertController(title: "날짜 선택", message: nil, preferredStyle: .alert)
                
                alert.addDatePicker(date: selectedDate) {
                    let dateString = dateFormatter.string(from: $0)
                    self?.dateChangeButton.setTitle(dateString, for: .normal)
                    textRelay.accept(dateString)
                }
                
                let action = UIAlertAction(title: "선택", style: .default)
                
                alert.addAction(action)
                self?.present(alert, animated: true)
            }).disposed(by: disposeBag)
        
        let moneyTextFieldRelay = BehaviorRelay<String?>(value: moneyTextField.text)
        moneyTextField.rx.text
            .orEmpty
            .filter { $0 != "" && $0 != "0" && $0.count <= 10}
            .subscribe(onNext: {
                moneyTextFieldRelay.accept($0)
            })
            .disposed(by: disposeBag)
        
        let scrollViewContentSize = chartScrollView.rx.observe(CGSize.self, "contentSize")
        
        let scrollViewDidAppear = Observable.combineLatest(scrollViewContentSize, chartScrollView.rx.contentOffset)
            .skip(1)
            .map { contentSize, offset -> (Double, Double) in
                guard let contentWidth = contentSize?.width else {
                    return (0, Double(offset.x))
                }
                
                return (Double(contentWidth), Double(offset.x))
            }
        
        let didTapScrollView = Observable.combineLatest(scrollViewContentSize, chartScrollView.touchPointRelay) 
            .map { contentSize, touchPointX -> (Double, Double) in
                guard let contentWidth = contentSize?.width else {
                    return (0, touchPointX)
                }
                
                return (Double(contentWidth), touchPointX)
            }
        
        let input = HuhoeDetailViewModel.Input(
            changeDate: textRelay.asObservable(),
            changeMoney: moneyTextFieldRelay.asObservable().filterNil(),
            viewDidAppear: Observable.empty(),
            scrollViewDidAppear: scrollViewDidAppear,
            didTapScrollView: didTapScrollView.asObservable()
        )
        
        // MARK: - Output
        
        guard let output = viewModel?.transform(input) else {
            return
        }
        
        output.realTimePrice
            .observe(on: MainScheduler.asyncInstance)
            .bind(to: currentPriceLabel.rx.text)
            .disposed(by: disposeBag)
        
        output.priceAndQuantity
            .asDriver(onErrorJustReturn: (Double.zero, Double.zero))
            .drive(onNext: { [weak self] price, quantity in
                self?.pastPriceLabel.text = price.toString(digit: 4) + " 원"
                self?.pastQuantityLabel.text = String(format: "%.4f", quantity) + (" \(output.symbol)")
            })
            .disposed(by: disposeBag)
        
        Observable.combineLatest(output.currentCoinHistoryInformation, output.pastCoinHistoryInformation)
            .observe(on: MainScheduler.asyncInstance)
            .take(1)
            .subscribe(onNext: { [weak self] current, past in
                self?.applySnapShot(current, past)
            })
            .disposed(by: disposeBag)
        
        Observable.combineLatest(output.todayCoinHistoryInformation, output.pastCoinHistoryInformation)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(onNext: { [weak self] today, past in
                self?.applySnapShot(today, past)
            })
            .disposed(by: disposeBag)
        
        output.coinHistory
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(onNext: { [weak self] coinHistory in
                let xUnit: Double = UIScreen.main.bounds.width / CGFloat(30)
                self?.chartImageView.getSize(numberOfData: coinHistory.price.count, xUnit: xUnit.rounded(.down))
            })
            .disposed(by: disposeBag)
        
        output.chartInformation
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(onNext: { [weak self] chartInformation in
                self?.chartOldDateLabel.text = chartInformation.oldestDate
                self?.chartLatestDateLabel.text = chartInformation.latestDate
                
                self?.chartImageView.drawChart(
                    price: chartInformation.price,
                    offsetX: chartInformation.pointX
                )
            })
            .disposed(by: disposeBag)
        
        output.chartPriceAndDateViewInformation
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(onNext: { [weak self] chartPriceAndDateViewInformation in
                let price = chartPriceAndDateViewInformation.price
                let date = chartPriceAndDateViewInformation.date
                let pointX = chartPriceAndDateViewInformation.pointX
                
                self?.chartScrollView.moveFloatingPriceAndDateView(offsetX: pointX, price: price, date: date)
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - Configure View

extension HuhoeDetailViewController {
    private func configureBackButton() {
        navigationController?.navigationBar.tintColor = .label
        navigationController?.navigationBar.topItem?.title = String()
    }
    
    private func configureDateChangeButton() {
        dateChangeButton.layer.cornerRadius = 6
    }
    
    private func configureCollectionView() {
        configureCollectionViewLayout()
        configureCollectionViewDataSource()
        
        coinHistoryCollectionView.keyboardDismissMode = .onDrag
    }
    
    private func configureLabel() {
        currentPriceLabel.font = .preferredFont(forTextStyle: .title1).bold
    }
    
    private func configureChartView() {
        UIView.animate(withDuration: 0.0, animations: {
            self.chartScrollView.transform = CGAffineTransform(rotationAngle: .pi)
            self.chartImageView.transform = CGAffineTransform(rotationAngle: .pi)
        })
    }
}

// MARK: - Collecion View Methods

extension HuhoeDetailViewController {
    private func configureCollectionViewLayout() {
        var listConfig = UICollectionLayoutListConfiguration(appearance: .plain)
        listConfig.showsSeparators = false
        coinHistoryCollectionView.collectionViewLayout = UICollectionViewCompositionalLayout.list(using: listConfig)
    }
    
    private func configureCollectionViewDataSource() {
        typealias CellRegistration = UICollectionView.CellRegistration<CoinHistoryCell, CoinHistoryItem>
        
        let cellNib = UINib(nibName: CoinHistoryCell.identifier, bundle: nil)
        
        let coinListRegistration = CellRegistration(cellNib: cellNib) { cell, indexPath, item in
            cell.configureCell(item: item)
        }
        
        dataSource = DiffableDataSource(collectionView: coinHistoryCollectionView) { collectionView, indexPath, item in
            return collectionView.dequeueConfiguredReusableCell(
                using: coinListRegistration,
                for: indexPath,
                item: item
            )
        }
    }
    
    private func applySnapShot(_ today: CoinHistoryItem, _ past: [CoinHistoryItem]) {
        var snapShot = NSDiffableDataSourceSnapshot<Section, CoinHistoryItem>()
        
        snapShot.appendSections([.today])
        snapShot.appendItems([today], toSection: .today)
        
        snapShot.appendSections([.past])
        snapShot.appendItems(past, toSection: .past)
        
        dataSource?.apply(snapShot)
    }
}

// MARK: - Keyboard

extension HuhoeDetailViewController {
    private func bindTapGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: nil)
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
        
        tapGesture.rx.event
            .subscribe(onNext: { [weak self] _ in
                self?.view.endEditing(true)
            })
            .disposed(by: disposeBag)
    }
}


// MARK: - Private Extension

private extension UIAlertController {
    func addDatePicker(
        date: Date?,
        action: DatePickerViewController.Action?
    ) {
        let datePicker = DatePickerViewController(date: date, action: action)
        setValue(datePicker, forKey: "contentViewController")
    }
}

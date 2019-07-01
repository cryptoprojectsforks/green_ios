import Foundation
import UIKit
import NVActivityIndicatorView
import PromiseKit

class SettingsViewController: UIViewController {

    @IBOutlet weak var tableView: UITableView!

    var items = [SettingsItem]()
    var sections = [SettingsSections]()
    var data: [SettingsSections: Any] = [:]
    var username: String?
    var twoFactorConfig: TwoFactorConfig?
    var isResetActive: Bool {
        get {
            guard let twoFactorConfig = getGAService().getTwoFactorReset() else { return false }
            return twoFactorConfig.isResetActive
        }
    }
    var isDisputeActive: Bool {
        get {
            guard let twoFactorConfig = getGAService().getTwoFactorReset() else { return false }
            return twoFactorConfig.isDisputeActive
        }
    }
    var isWatchOnly: Bool { get { return getGAService().isWatchOnly } }
    var isLiquid: Bool { get { return getGdkNetwork(getNetwork()).liquid } }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.title = NSLocalizedString("id_settings", comment: "")
        tableView.delegate = self
        tableView.dataSource = self
        tableView.estimatedRowHeight = 75
        tableView.rowHeight = 75
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let controller = self.tabBarController as? TabViewController else { return }
        controller.snackbar.isHidden = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard let controller = self.tabBarController as? TabViewController else { return }
        controller.snackbar.isHidden = true
    }

    func reloadData() {
        let bgq = DispatchQueue.global(qos: .background)
        let isWatchOnly = getGAService().isWatchOnly
        let session = getGAService().getSession()
        Guarantee().compactMap(on: bgq) {
            if !isWatchOnly {
                self.username = try session.getWatchOnlyUsername()
                let dataTwoFactorConfig = try session.getTwoFactorConfig()
                self.twoFactorConfig = try JSONDecoder().decode(TwoFactorConfig.self, from: JSONSerialization.data(withJSONObject: dataTwoFactorConfig!, options: []))
            }
            return ()
        }.done {
            self.sections = self.getSections()
            self.items = self.getSettings()
            self.data = Dictionary(grouping: self.items) { (item) in
                return item.section
            }
            self.tableView.reloadData()
        }.catch { _ in }
    }

    func getSections() -> [SettingsSections] {
        if isWatchOnly {
            return [.network, .about]
        } else if isResetActive {
            return [.network, .twoFactor, .about]
        }
        return [.network, .account, .twoFactor, .security, .advanced, .about]
    }

    func getNetworks() -> [SettingsItem] {
        let setupPin = SettingsItem(
            title: String(format: NSLocalizedString(AuthenticationTypeHandler.supportsBiometricAuthentication() ? "id_setup_pin_and_s" : "id_setup_pin", comment: ""), NSLocalizedString(AuthenticationTypeHandler.biometryType == .faceID ? "id_face_id" : "id_touch_id", comment: "")),
            subtitle: "",
            section: .network,
            type: .SetupPin)
        let watchOnly = SettingsItem(
            title: NSLocalizedString("id_watchonly_login", comment: ""),
            subtitle: String(format: NSLocalizedString((username == nil || username!.isEmpty) ? "id_set_up_watchonly_credentials" : "id_enabled_1s", comment: ""), username ?? ""),
            section: .network,
            type: .WatchOnly)
        let logout = SettingsItem(
            title: String(format: NSLocalizedString("id_s_network", comment: ""), getNetwork()).localizedCapitalized,
            subtitle: NSLocalizedString("id_log_out", comment: ""),
            section: .network,
            type: .Logout)
        let switchNetwork = SettingsItem(
            title: String(format: NSLocalizedString("id_switch_network", comment: ""), getNetwork()).localizedCapitalized,
            subtitle: "",
            section: .network,
            type: .SwitchNetwork)
        if isWatchOnly || isResetActive {
            return [logout, switchNetwork]
        } else if isLiquid {
            return [setupPin, logout, switchNetwork]
        }
        return [setupPin, watchOnly, logout, switchNetwork]
    }

    func getAccount() -> [SettingsItem] {
        guard let settings = getGAService().getSettings() else { return [] }
        let bitcoinDenomination = SettingsItem(
            title: NSLocalizedString("id_bitcoin_denomination", comment: ""),
            subtitle: settings.denomination.string,
            section: .account,
            type: .BitcoinDenomination)

        let referenceExchangeRate = SettingsItem(
            title: NSLocalizedString("id_reference_exchange_rate", comment: ""),
            subtitle: String(format: NSLocalizedString("id_s_from_s", comment: ""), settings.pricing["currency"]!, settings.pricing["exchange"]!),
            section: .account,
            type: .ReferenceExchangeRate)

        let defaultTransactionPriority = SettingsItem(
            title: NSLocalizedString("id_default_transaction_priority", comment: ""),
            subtitle: settings.transactionPriority.description,
            section: .account,
            type: .DefaultTransactionPriority)

        let defaultCustomFeeRate = SettingsItem(
            title: NSLocalizedString("id_default_custom_fee_rate", comment: ""),
            subtitle: String(format: "%.02f satoshi / vbyte", Float(settings.customFeeRate ?? 1000)/1000),
            section: .account,
            type: .DefaultCustomFeeRate)

        if isWatchOnly && isResetActive {
            return []
        } else if isLiquid {
            return [bitcoinDenomination, defaultTransactionPriority, defaultCustomFeeRate]
        }
        return [bitcoinDenomination, referenceExchangeRate, defaultTransactionPriority, defaultCustomFeeRate]
    }

    func getTwoFactor() -> [SettingsItem] {
        guard let settings = getGAService().getSettings() else { return [] }
        let setupTwoFactor = SettingsItem(
            title: NSLocalizedString("id_twofactor_authentication", comment: ""),
            subtitle: NSLocalizedString("id_set_up_twofactor_authentication", comment: ""),
            section: .twoFactor,
            type: .SetupTwoFactor)
        var thresholdValue = ""
        var locktimeRecoveryEnable = false
        if let twoFactorConfig = self.twoFactorConfig {
            let limits = twoFactorConfig.limits
            if limits.isFiat == true {
                thresholdValue = String(format: "%@ %@", limits.fiat, settings.getCurrency())
            } else {
                thresholdValue = String(format: "%@ %@", limits.get(TwoFactorConfigLimits.CodingKeys(rawValue: settings.denomination.rawValue)!)!, settings.denomination.string)
            }
            if let notifications = settings.notifications {
                locktimeRecoveryEnable = notifications.emailOutgoing == true
            }
        }
        let thresholdTwoFactor = SettingsItem(
            title: NSLocalizedString("id_twofactor_threshold", comment: ""),
            subtitle: String(format: NSLocalizedString(thresholdValue == "" ? "id_set_twofactor_threshold" : "id_your_twofactor_threshold_is_s", comment: ""), thresholdValue),
            section: .twoFactor,
            type: .ThresholdTwoFactor)
        let locktimeRecovery = SettingsItem(
            title: NSLocalizedString("id_recovery_transaction_emails", comment: ""),
            subtitle: locktimeRecoveryEnable ? NSLocalizedString("id_enabled", comment: "") : NSLocalizedString("id_disabled", comment: ""),
            section: .twoFactor,
            type: .LockTimeRecovery)
        let locktimeRequest = SettingsItem(
            title: NSLocalizedString("id_request_recovery_transactions", comment: ""),
            subtitle: "",
            section: .twoFactor,
            type: .LockTimeRequest)
        let resetTwoFactor = SettingsItem(
            title: NSLocalizedString("id_request_twofactor_reset", comment: ""),
            subtitle: "",
            section: .twoFactor,
            type: .ResetTwoFactor)
        let disputeTwoFactor = SettingsItem(
            title: NSLocalizedString("id_dispute_twofactor_reset", comment: ""),
            subtitle: "",
            section: .twoFactor,
            type: .DisputeTwoFactor)
        let cancelTwoFactor = SettingsItem(
            title: NSLocalizedString("id_cancel_twofactor_reset", comment: ""),
            subtitle: "",
            section: .twoFactor,
            type: .CancelTwoFactor)

        if isWatchOnly {
            return []
        } else if isResetActive && !isDisputeActive {
            return [disputeTwoFactor, cancelTwoFactor]
        } else if isResetActive && isDisputeActive {
            return [cancelTwoFactor]
        } else if isLiquid {
            return [setupTwoFactor]
        }
        var menu = [SettingsItem]()
        menu.append(contentsOf: [setupTwoFactor])
        if twoFactorConfig?.anyEnabled ?? false {
            menu.append(contentsOf: [thresholdTwoFactor])
            if twoFactorConfig?.enableMethods.contains("email") ?? false {
                menu.append(contentsOf: [locktimeRecovery, locktimeRequest])
            }
            menu.append(contentsOf: [resetTwoFactor])
        }
        return menu
    }

    func getSecurity() -> [SettingsItem] {
        guard let settings = getGAService().getSettings() else { return [] }
        let mnemonic = SettingsItem(
            title: NSLocalizedString("id_mnemonic", comment: ""),
            subtitle: NSLocalizedString("id_touch_to_display", comment: ""),
            section: .security,
            type: .Mnemonic)
        let autolock = SettingsItem(
            title: NSLocalizedString("id_auto_logout_timeout", comment: ""),
            subtitle: settings.autolock.string,
            section: .security,
            type: .Autolock)
        return !isWatchOnly && !isResetActive ? [mnemonic, autolock] : []
    }

    func getAdvanced() -> [SettingsItem] {
        let pgp = SettingsItem(
            title: NSLocalizedString("id_pgp_key", comment: ""),
            subtitle: NSLocalizedString("id_set_up_pgp_key_for", comment: ""),
            section: .advanced,
            type: .Pgp)
        let sweep = SettingsItem(
            title: NSLocalizedString("id_sweep", comment: ""),
            subtitle: NSLocalizedString("id_sweep_from_paper_wallet", comment: ""),
            section: .advanced,
            type: .Sweep)

        var advanced = [SettingsItem]()
        if !isWatchOnly && !isResetActive {
            advanced.append(pgp)
        }
        if !isLiquid {
            advanced.append(sweep)
        }
        return advanced
    }

    func getAbout() -> [SettingsItem] {
        let versionSubtitle = String(format: NSLocalizedString("id_version_1s", comment: ""), Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? CVarArg ?? "")
        let version = SettingsItem(
            title: NSLocalizedString("id_version", comment: ""),
            subtitle: versionSubtitle,
            section: .about,
            type: .Version)
        let termOfUse = SettingsItem(
            title: NSLocalizedString("id_terms_of_use", comment: ""),
            subtitle: "",
            section: .about,
            type: .TermsOfUse)
        let privacyPolicy = SettingsItem(
            title: NSLocalizedString("id_privacy_policy", comment: ""),
            subtitle: "",
            section: .about,
            type: .PrivacyPolicy)
        return [version, termOfUse, privacyPolicy]
    }

    func getSettings() -> [SettingsItem] {
        var menu = [SettingsItem]()
        menu.append(contentsOf: getNetworks())
        menu.append(contentsOf: getAccount())
        menu.append(contentsOf: getTwoFactor())
        menu.append(contentsOf: getSecurity())
        menu.append(contentsOf: getAdvanced())
        menu.append(contentsOf: getAbout())
        return menu
    }

    func toString(_ section: SettingsSections) -> String {
        let strings: [SettingsSections: String] = [.about: "id_about", .account: "id_account", .advanced: "id_advanced", .network: "id_network", .security: "id_security", .twoFactor: "id_twofactor"]
        return NSLocalizedString(strings[section]!, comment: "")
    }

    func getHeaderImage(from sectionIndex: Int) -> UIImage {
        let icons: [SettingsSections: String] = [.about: "about", .account: "account", .advanced: "advanced", .network: "network", .security: "security", .twoFactor: "twofactor"]
        let section: SettingsSections = sections[sectionIndex]
        return UIImage(named: icons[section]!)!
    }
}

extension SettingsViewController {

    func logout() {
        let bgq = DispatchQueue.global(qos: .background)
        Guarantee().map {
            self.startAnimating()
        }.map(on: bgq) {
            try getSession().disconnect()
        }.ensure {
            self.stopAnimating()
        }.done {
            getGAService().reset()
            getAppDelegate()!.instantiateViewControllerAsRoot(storyboard: "Main", identifier: "InitialViewController")
        }.catch { _ in
            print("disconnection error never happens")
        }
    }

    func setWatchOnly(username: String, password: String) {
        if username.isEmpty {
            self.showAlert(title: NSLocalizedString("id_error", comment: ""), message: NSLocalizedString("id_enter_a_valid_username", comment: ""))
            return
        } else if password.isEmpty {
            self.showAlert(title: NSLocalizedString("id_error", comment: ""), message: NSLocalizedString("id_the_password_cant_be_empty", comment: ""))
            return
        }
        let bgq = DispatchQueue.global(qos: .background)
        firstly {
            self.startAnimating()
            return Guarantee()
        }.compactMap(on: bgq) {
            try getGAService().getSession().setWatchOnly(username: username, password: password)
        }.ensure {
            self.stopAnimating()
        }.done { _ in
            self.reloadData()
        }.catch {_ in
            self.showAlert(title: NSLocalizedString("id_error", comment: ""), message: NSLocalizedString("id_username_not_available", comment: ""))
        }
    }

    func setCancelTwoFactor() {
        let bgq = DispatchQueue.global(qos: .background)
        firstly {
            self.startAnimating()
            return Guarantee()
        }.compactMap(on: bgq) {
            try getGAService().getSession().cancelTwoFactorReset()
        }.then(on: bgq) { call in
            call.resolve(self)
        }.ensure {
            self.stopAnimating()
        }.done { _ in
            self.logout()
        }.catch {_ in
            self.showAlert(title: NSLocalizedString("id_error", comment: ""), message: NSLocalizedString("id_cancel_twofactor_reset", comment: ""))
        }
    }

    func setLockTimeRequest() {
        let bgq = DispatchQueue.global(qos: .background)
        firstly {
            self.startAnimating()
            return Guarantee()
        }.compactMap(on: bgq) {
            return try getSession().sendNlocktimes()
        }.ensure {
            self.stopAnimating()
        }.done { _ in
            self.showAlert(title: NSLocalizedString("id_request_sent", comment: ""), message: NSLocalizedString("id_recovery_transaction_request", comment: ""))
        }.catch {_ in
            self.showAlert(title: NSLocalizedString("id_error", comment: ""), message: NSLocalizedString("id_request_failure", comment: ""))
        }
    }

    func changeSettings(_ settings: Settings) {
        let details = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(settings), options: .allowFragments) as? [String: Any]
        let session = getGAService().getSession()
        let bgq = DispatchQueue.global(qos: .background)
        Guarantee().map {_ in
            self.startAnimating()
        }.compactMap(on: bgq) { _ in
            try session.changeSettings(details: details!)
        }.then(on: bgq) { call in
            call.resolve(self)
        }.ensure {
            self.stopAnimating()
        }.done { _ in
            self.reloadData()
        }.catch { error in
            self.showAlert(error)
        }
    }

    func resetTwoFactor(email: String, isDispute: Bool) {
        let session = getGAService().getSession()
        let bgq = DispatchQueue.global(qos: .background)
        Guarantee().map {_ in
            self.startAnimating()
        }.compactMap(on: bgq) { _ in
            try session.resetTwoFactor(email: email, isDispute: false)
        }.then(on: bgq) { call in
            call.resolve(self)
        }.ensure {
            self.stopAnimating()
        }.done { _ in
            self.logout()
        }.catch { error in
            self.showAlert(error)
        }
    }
}

extension SettingsViewController {

    func showAlert(_ error: Error) {
        let text: String
        if let error = error as? TwoFactorCallError {
            switch error {
            case .failure(let localizedDescription), .cancel(let localizedDescription):
                text = localizedDescription
            }
            self.showAlert(title: NSLocalizedString("id_error", comment: ""), message: text)
        }
    }

    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: NSLocalizedString("id_continue", comment: ""), style: .cancel) { _ in })
        self.present(alert, animated: true, completion: nil)
    }

    func showLockTimeRecovery() {
        let settings = getGAService().getSettings()!
        var enabled = false
        if let notifications = settings.notifications {
            enabled = notifications.emailOutgoing == true
        }
        let alert = UIAlertController(title: NSLocalizedString("id_recovery_transaction_emails", comment: ""), message: "", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: NSLocalizedString("id_enable", comment: ""), style: enabled ? .destructive : .default) { _ in
            let notifications = ["email_incoming": true, "email_outgoing": true]
            let json = try! JSONSerialization.data(withJSONObject: notifications, options: [])
            settings.notifications = try! JSONDecoder().decode(SettingsNotifications.self, from: json)
            self.changeSettings(settings)
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("id_disable", comment: ""), style: !enabled ? .destructive : .default) { _ in
            let notifications = ["email_incoming": false, "email_outgoing": false]
            let json = try! JSONSerialization.data(withJSONObject: notifications, options: [])
            settings.notifications = try! JSONDecoder().decode(SettingsNotifications.self, from: json)
            self.changeSettings(settings)
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("id_cancel", comment: ""), style: .cancel) { _ in })
        self.present(alert, animated: true, completion: nil)
    }

    func showDefaultTransactionPriority() {
        let list = [TransactionPriority.High.text, TransactionPriority.Medium.text, TransactionPriority.Low.text]
        let settings = getGAService().getSettings()!
        let selected = settings.transactionPriority.text
        let alert = UIAlertController(title: NSLocalizedString("id_default_transaction_priority", comment: ""), message: "", preferredStyle: .actionSheet)
        list.forEach { (item: String) in
            alert.addAction(UIAlertAction(title: NSLocalizedString(item, comment: ""), style: item == selected  ? .destructive : .default) { _ in
                settings.transactionPriority = TransactionPriority.from(item)
                self.changeSettings(settings)
            })
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("id_cancel", comment: ""), style: .cancel) { _ in })
        self.present(alert, animated: true, completion: nil)
    }

    func showBitcoinDenomination() {
        var list = [DenominationType.BTC.string, DenominationType.MilliBTC.string, DenominationType.MicroBTC.string]
        if !isLiquid {
            list.append(DenominationType.Bits.string)
        }
        let settings = getGAService().getSettings()!
        let selected = settings.denomination.string
        let alert = UIAlertController(title: NSLocalizedString("id_bitcoin_denomination", comment: ""), message: "", preferredStyle: .actionSheet)
        list.forEach { (item: String) in
            alert.addAction(UIAlertAction(title: item, style: item == selected  ? .destructive : .default) { _ in
                settings.denomination = DenominationType.from(item)
                self.changeSettings(settings)
            })
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("id_cancel", comment: ""), style: .cancel) { _ in })
        self.present(alert, animated: true, completion: nil)
    }

    func showDefaultCustomRate() {
        let settings = getGAService().getSettings()!
        let hint = String(format: "%.02f", Float(settings.customFeeRate ?? 1000) / 1000)

        let alert = UIAlertController(title: NSLocalizedString("id_default_custom_fee_rate", comment: ""), message: "", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = hint
            textField.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("id_cancel", comment: ""), style: .cancel) { _ in })
        alert.addAction(UIAlertAction(title: NSLocalizedString("id_save", comment: ""), style: .default) { _ in
            let textField = alert.textFields!.first
            let value = textField!.text
            let amount = value!.replacingOccurrences(of: ",", with: ".")
            guard let feeRate = Double(amount) else { return }
            settings.customFeeRate = UInt64(feeRate * 1000)
            self.changeSettings(settings)
        })
        self.present(alert, animated: true, completion: nil)
    }

    func showWatchOnly() {
        let alert = UIAlertController(title: NSLocalizedString("id_set_up_watchonly", comment: ""), message: NSLocalizedString("id_allows_you_to_quickly_check", comment: ""), preferredStyle: .alert)
        alert.addTextField { (textField) in textField.placeholder = NSLocalizedString("id_username", comment: "") }
        alert.addTextField { (textField) in textField.placeholder = NSLocalizedString("id_password", comment: "") }
        alert.addAction(UIAlertAction(title: NSLocalizedString("id_cancel", comment: ""), style: .cancel) { _ in })
        alert.addAction(UIAlertAction(title: NSLocalizedString("id_save", comment: ""), style: .default) { _ in
            let username = alert.textFields![0].text!
            let password = alert.textFields![1].text!
            self.setWatchOnly(username: username, password: password)
        })
        self.present(alert, animated: true, completion: nil)
    }

    func showAutolock() {
        let list = [AutoLockType.minute.string, AutoLockType.twoMinutes.string, AutoLockType.fiveMinutes.string, AutoLockType.tenMinutes.string]
        let settings = getGAService().getSettings()!
        let selected = settings.autolock.string
        let alert = UIAlertController(title: NSLocalizedString("id_auto_logout_timeout", comment: ""), message: "", preferredStyle: .actionSheet)
        list.forEach { (item: String) in
            alert.addAction(UIAlertAction(title: item, style: item == selected  ? .destructive : .default) { _ in
                settings.autolock = AutoLockType.from(item)
                self.changeSettings(settings)
            })
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("id_cancel", comment: ""), style: .cancel) { _ in })
        self.present(alert, animated: true, completion: nil)
    }

    func showResetTwoFactor() {
        let hint = "jane@example.com"
        let alert = UIAlertController(title: NSLocalizedString("id_request_twofactor_reset", comment: ""), message: NSLocalizedString("id_resetting_your_twofactor_takes", comment: ""), preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = hint
            textField.keyboardType = .emailAddress
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("id_cancel", comment: ""), style: .cancel) { _ in })
        alert.addAction(UIAlertAction(title: NSLocalizedString("id_save", comment: ""), style: .default) { _ in
            let textField = alert.textFields!.first
            let email = textField!.text
            self.resetTwoFactor(email: email!, isDispute: false)
        })
        self.present(alert, animated: true, completion: nil)
    }

    func showDisputeTwoFactor() {
        let hint = "jane@example.com"
        let alert = UIAlertController(title: NSLocalizedString("id_dispute_twofactor_reset", comment: ""), message: NSLocalizedString("id_warning_there_is_already_a", comment: ""), preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = hint
            textField.keyboardType = .emailAddress
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("id_cancel", comment: ""), style: .cancel) { _ in })
        alert.addAction(UIAlertAction(title: NSLocalizedString("id_save", comment: ""), style: .default) { _ in
            let textField = alert.textFields!.first
            let email = textField!.text
            self.resetTwoFactor(email: email!, isDispute: true)
        })
        self.present(alert, animated: true, completion: nil)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let controller = segue.destination as? EnableTwoFactorViewController {
            controller.isHiddenWalletButton = true
        }

        if let controller = segue.destination as? WalletsViewController {
            controller.isSweep = true
        }

        if let controller = segue.destination as? NetworkSelectionSettings {
            controller.saveTitle = NSLocalizedString("id_logout_and_switch", comment: "")
            controller.onSave = {
                let network = getNetwork()
                onFirstInitialization(network: network)
                self.logout()
            }
        }
    }
}

extension SettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        view.backgroundColor = UIColor.customTitaniumDark()
        view.tintColor = UIColor.customMatrixGreen()
        guard let header = view as? UITableViewCell else { return }
        header.textLabel?.textColor = UIColor.customMatrixGreen()
        header.textLabel?.font = UIFont.systemFont(ofSize: 16.00, weight: .light)
        header.textLabel?.adjustsFontSizeToFitWidth = true
        header.textLabel?.minimumScaleFactor = 0.5
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = UITableViewCell()
        header.textLabel?.text = toString(sections[section])
        header.imageView?.image = getHeaderImage(from: section)
        header.isUserInteractionEnabled = false
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 43
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let section = sections[indexPath.section]
        let itemsInSection = data[section] as? [SettingsItem]
        let item = itemsInSection![indexPath.row]
        switch item.type {
        case .BitcoinDenomination: showBitcoinDenomination()
        case .SetupPin: performSegue(withIdentifier: "screenLock", sender: nil)
        case .Logout: logout()
        case .SwitchNetwork: performSegue(withIdentifier: "network", sender: nil)
        case .WatchOnly: showWatchOnly()
        case .ReferenceExchangeRate: performSegue(withIdentifier: "currency", sender: nil)
        case .DefaultTransactionPriority: showDefaultTransactionPriority()
        case .DefaultCustomFeeRate: showDefaultCustomRate()
        case .SetupTwoFactor: performSegue(withIdentifier: "setupTwoFactor", sender: nil)
        case .ThresholdTwoFactor: performSegue(withIdentifier: "twoFactorLimit", sender: nil)
        case .ResetTwoFactor: showResetTwoFactor()
        case .DisputeTwoFactor: showDisputeTwoFactor()
        case .CancelTwoFactor: setCancelTwoFactor()
        case .LockTimeRecovery: showLockTimeRecovery()
        case .LockTimeRequest: setLockTimeRequest()
        case .Mnemonic: performSegue(withIdentifier: "recovery", sender: nil)
        case .Autolock: showAutolock()
        case .Pgp: performSegue(withIdentifier: "pgp", sender: nil)
        case .Sweep: performSegue(withIdentifier: "sweep_to_wallets", sender: nil)
        case .TermsOfUse:
            UIApplication.shared.open(URL(string: "https://blockstream.com/green/terms/")!)
        case .PrivacyPolicy:
            UIApplication.shared.open(URL(string: "https://blockstream.com/green/privacy/")!)
        case .Version:
            break
        }
    }
}
extension SettingsViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let section = sections[section]
        let itemsInSection = data[section] as? [SettingsItem]
        return itemsInSection?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell",
                                          for: indexPath as IndexPath)
        let section = sections[indexPath.section]
        let itemsInSection = data[section] as? [SettingsItem]
        let item = itemsInSection![indexPath.row]
        cell.textLabel!.text = item.title
        cell.detailTextLabel?.text = item.subtitle
        cell.detailTextLabel?.numberOfLines = 2
        cell.detailTextLabel?.textColor = item.type == .Logout ? UIColor.errorRed() : UIColor.lightGray
        cell.selectionStyle = .none
        cell.accessoryType = item.type == .Version ? .none : .disclosureIndicator
        cell.setNeedsLayout()
        return cell
    }
}
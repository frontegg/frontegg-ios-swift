//
//  MainViewController.swift

import UIKit
import FronteggSwift

/// A view controller that displays the main content of the demo application.
/// This component handles the chat functionality and user interactions.
class MainViewController: BaseViewController, UITextFieldDelegate {
    var startingPoint: Int64 = .max
    @IBOutlet weak var messageTextView: UITextField!
    @IBOutlet weak var tblChat: UITableView!
    
    var parentVC : StreamViewController!
    
    var selectedSegment : Int = 0
    var selectedDropDown : Int = 0
    var selectedIndexpathForReaction : IndexPath!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    @objc func didTapOnView(){
        self.view.endEditing(true)
        self.selectedIndexpathForReaction = nil
    }
    
    
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }
    
    
    @IBAction func didTapSegmentOption(_ sender: UIButton) {
        self.selectedSegment = sender.tag
    }
    
}

/// A table view cell for the chat messages.
/// This component displays a single chat message in the table view.
class ChatTableViewCell : UITableViewCell{
    
    /// The width constraint for the emoji stack view
    @IBOutlet weak var emojiWidthConst: NSLayoutConstraint!
    /// The label for the message content
    @IBOutlet weak var lblMessage: UILabel!
    /// The label for the message timestamp
    @IBOutlet weak var lblTime: UILabel!
    /// The profile image view
    @IBOutlet weak var profileImage: UIImageView!
    /// The background view for the message
    @IBOutlet weak var bgView: UIView!
    /// The stack view for the emojis
    @IBOutlet weak var emojiStackView: UIStackView!
    
    /// Sets up the UI for the chat message cell.
    func setupUI(){
        self.emojiStackView.layer.borderColor = UIColor.lightGray.cgColor
        self.emojiStackView.layer.borderWidth = 0.5
        self.emojiStackView.backgroundColor = .clear
        self.emojiStackView.backgroundColor = .white
        self.emojiStackView.isHidden = true
        self.emojiStackView.layer.cornerRadius = self.emojiStackView.frame.height/2
        profileImage.layer.cornerRadius = profileImage.frame.height/2
        profileImage.clipsToBounds = true
        profileImage.contentMode = .scaleAspectFill
        bgView.layer.cornerRadius = 5
        lblMessage.numberOfLines = 0
    }
}

/// A collection view cell for the camera images.
/// This component displays a single camera image in the collection view.
class CameraCollectionCell : UICollectionViewCell{
    
    @IBOutlet weak var lblRoom: UILabel!
    @IBOutlet weak var cameraImg: UIImageView!
    @IBOutlet weak var lblCameraName: UILabel!
    
    /// Sets up the UI for the camera image cell.
    func setpUI(){
        self.cameraImg.backgroundColor = .themeBGColor
        self.cameraImg.layer.cornerRadius = 5
        self.lblCameraName.textColor = .black
        self.lblRoom.textColor = .themeTextGrayColor
    }
}

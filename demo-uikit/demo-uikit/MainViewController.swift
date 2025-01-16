//
//  MainViewController.swift

import UIKit
import FronteggSwift

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


class ChatTableViewCell : UITableViewCell{
    
    @IBOutlet weak var emojiWidthConst: NSLayoutConstraint!
    @IBOutlet weak var lblMessage: UILabel!
    @IBOutlet weak var lblTime: UILabel!
    @IBOutlet weak var profileImage: UIImageView!
    @IBOutlet weak var bgView: UIView!
    @IBOutlet weak var emojiStackView: UIStackView!
    
    
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

class CameraCollectionCell : UICollectionViewCell{
    
    @IBOutlet weak var lblRoom: UILabel!
    @IBOutlet weak var cameraImg: UIImageView!
    @IBOutlet weak var lblCameraName: UILabel!
    
    func setpUI(){
        self.cameraImg.backgroundColor = .themeBGColor
        self.cameraImg.layer.cornerRadius = 5
        self.lblCameraName.textColor = .black
        self.lblRoom.textColor = .themeTextGrayColor
    }
}

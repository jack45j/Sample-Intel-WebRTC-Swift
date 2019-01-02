//
//  ViewController.swift
//  testIntelWebRTC
//
//  Created by 林翌埕 on 2018/11/26.
//  Copyright © 2018 Benson Lin. All rights reserved.
//


import UIKit
import AFNetworking

class ViewController: UIViewController {
    
    @IBAction func pressedConnectButton(_ sender: Any) {
        performSegue(withIdentifier: "gogo", sender: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
}

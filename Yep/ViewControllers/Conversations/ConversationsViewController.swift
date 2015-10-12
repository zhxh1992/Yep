//
//  ConversationsViewController.swift
//  Yep
//
//  Created by NIX on 15/3/16.
//  Copyright (c) 2015年 Catch Inc. All rights reserved.
//

import UIKit
import RealmSwift

let YepNotificationCommentAction = "YepNotificationCommentAction"
let YepNotificationOKAction = "YepNotificationOKAction"

class ConversationsViewController: UIViewController {

    @IBOutlet weak var conversationsTableView: UITableView!

    let feedConversationDockCellID = "FeedConversationDockCell"
    let cellIdentifier = "ConversationCell"


    var realm: Realm!

    var realmNotificationToken: NotificationToken?

    var haveUnreadMessages = false {
        didSet {
            if haveUnreadMessages != oldValue {
                if haveUnreadMessages {
                    navigationController?.tabBarItem.image = UIImage(named: "icon_chat_unread")
                    navigationController?.tabBarItem.selectedImage = UIImage(named: "icon_chat_active_unread")

                } else {
                    navigationController?.tabBarItem.image = UIImage(named: "icon_chat")
                    navigationController?.tabBarItem.selectedImage = UIImage(named: "icon_chat_active")
                }

                reloadConversationsTableView()
            }
        }
    }

    lazy var noConversationFooterView: InfoView = InfoView(NSLocalizedString("Have a nice day!", comment: ""))

    var noConversation = false {
        didSet {
            if noConversation != oldValue {
                conversationsTableView.tableFooterView = noConversation ? noConversationFooterView : UIView()
            }
        }
    }

    lazy var conversations: Results<Conversation> = {
        //return self.realm.objects(Conversation).sorted("updatedUnixTime", ascending: false)
//        let predicate = NSPredicate(format: "type = %d", ConversationType.OneToOne.rawValue)
        return self.realm.objects(Conversation).sorted("updatedUnixTime", ascending: false)
        }()

    struct Listener {
        static let Nickname = "ConversationsViewController.Nickname"
        static let Avatar = "ConversationsViewController.Avatar"

        static let isFetchingUnreadMessages = "ConversationsViewController.isFetchingUnreadMessages"
    }

    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)

        YepUserDefaults.avatarURLString.removeListenerWithName(Listener.Avatar)
        YepUserDefaults.nickname.removeListenerWithName(Listener.Nickname)

        isFetchingUnreadMessages.removeListenerWithName(Listener.isFetchingUnreadMessages)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        realm = try! Realm()

        NSNotificationCenter.defaultCenter().addObserver(self, selector: "reloadConversationsTableView", name: YepNewMessagesReceivedNotification, object: nil)
        
        YepUserDefaults.nickname.bindListener(Listener.Nickname) { [weak self] _ in
            dispatch_async(dispatch_get_main_queue()) {
                self?.reloadConversationsTableView()
            }
        }

        YepUserDefaults.avatarURLString.bindListener(Listener.Avatar) { [weak self] _ in
            dispatch_async(dispatch_get_main_queue()) {
                self?.reloadConversationsTableView()
            }
        }

        isFetchingUnreadMessages.bindListener(Listener.isFetchingUnreadMessages) { [weak self] isFetching in
            dispatch_async(dispatch_get_main_queue()) {
                println("isFetchingUnreadMessages: \(isFetching)")

                if isFetching {
                    self?.navigationItem.titleView = ActivityIndicatorTitleView(frame: CGRect(x: 0, y: 0, width: 120, height: 30))

                } else {
                    self?.navigationItem.titleView = nil
                }
            }
        }

        view.backgroundColor = UIColor.whiteColor()

        conversationsTableView.separatorColor = UIColor.yepCellSeparatorColor()
        conversationsTableView.separatorInset = YepConfig.ContactsCell.separatorInset

        conversationsTableView.registerNib(UINib(nibName: feedConversationDockCellID, bundle: nil), forCellReuseIdentifier: feedConversationDockCellID)
        conversationsTableView.registerNib(UINib(nibName: cellIdentifier, bundle: nil), forCellReuseIdentifier: cellIdentifier)
        conversationsTableView.rowHeight = 80
        conversationsTableView.tableFooterView = UIView()

        noConversation = conversations.isEmpty

        realmNotificationToken = realm.addNotificationBlock { [weak self] notification, realm in
            if let strongSelf = self {
                strongSelf.haveUnreadMessages = countOfUnreadMessagesInRealm(realm) > 0

                strongSelf.noConversation = strongSelf.conversations.isEmpty
            }
        }
    }

    private func cacheInAdvance() {

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {

            // 聊天界面的头像

            for user in normalUsers() {
                AvatarCache.sharedInstance.roundAvatarOfUser(user, withRadius: YepConfig.chatCellAvatarSize() * 0.5, completion: { _ in
                })
            }

            // 每个对话的最近 10 条消息（image or thumbnail）

            guard let realm = try? Realm() else {
                return
            }

            for conversation in realm.objects(Conversation) {

                let messages = messagesOfConversation(conversation, inRealm: realm)

                let latestBatch = min(10, messages.count)

                let messageImagePreferredWidth = YepConfig.ChatCell.mediaPreferredWidth
                let messageImagePreferredHeight = YepConfig.ChatCell.mediaPreferredHeight

                for i in (messages.count - latestBatch)..<messages.count {

                    let message = messages[i]

                    if let user = message.fromFriend {

                        let tailDirection: MessageImageTailDirection = user.friendState != UserFriendState.Me.rawValue ? .Left : .Right

                        switch message.mediaType {

                        case MessageMediaType.Image.rawValue:

                            if let (imageWidth, imageHeight) = imageMetaOfMessage(message) {

                                let aspectRatio = imageWidth / imageHeight

                                let messageImagePreferredWidth = max(messageImagePreferredWidth, ceil(YepConfig.ChatCell.mediaMinHeight * aspectRatio))
                                let messageImagePreferredHeight = max(messageImagePreferredHeight, ceil(YepConfig.ChatCell.mediaMinWidth / aspectRatio))

                                if aspectRatio >= 1 {
                                    ImageCache.sharedInstance.imageOfMessage(message, withSize: CGSize(width: messageImagePreferredWidth, height: ceil(messageImagePreferredWidth / aspectRatio)), tailDirection: tailDirection, completion: { _ in
                                    })

                                } else {
                                    ImageCache.sharedInstance.imageOfMessage(message, withSize: CGSize(width: messageImagePreferredHeight * aspectRatio, height: messageImagePreferredHeight), tailDirection: tailDirection, completion: { _ in
                                    })
                                }
                            }

                        case MessageMediaType.Video.rawValue:

                            if let (videoWidth, videoHeight) = videoMetaOfMessage(message) {
                                let aspectRatio = videoWidth / videoHeight

                                let messageImagePreferredWidth = max(messageImagePreferredWidth, ceil(YepConfig.ChatCell.mediaMinHeight * aspectRatio))
                                let messageImagePreferredHeight = max(messageImagePreferredHeight, ceil(YepConfig.ChatCell.mediaMinWidth / aspectRatio))

                                if aspectRatio >= 1 {
                                    ImageCache.sharedInstance.imageOfMessage(message, withSize: CGSize(width: messageImagePreferredWidth, height: ceil(messageImagePreferredWidth / aspectRatio)), tailDirection: tailDirection, completion: { _ in
                                    })

                                } else {
                                    ImageCache.sharedInstance.imageOfMessage(message, withSize: CGSize(width: messageImagePreferredHeight * aspectRatio, height: messageImagePreferredHeight), tailDirection: tailDirection, completion: { _ in
                                    })
                                }
                            }

                        default:
                            break
                        }
                    }
                }
            }
        }
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        //Make sure unread message refreshed
        reloadConversationsTableView()
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        
        if #available(iOS 9.0, *) {
            
            let replyAction = UIMutableUserNotificationAction()
            replyAction.title = NSLocalizedString("Reply", comment: "")
            replyAction.identifier = YepNotificationCommentAction
            replyAction.activationMode = .Background
            replyAction.behavior = .TextInput
            replyAction.authenticationRequired = false
            
            let replyOKAction = UIMutableUserNotificationAction()
            replyOKAction.title = "OK"
            replyOKAction.identifier = YepNotificationOKAction
            replyOKAction.activationMode = .Background
            replyOKAction.behavior = .Default
            replyOKAction.authenticationRequired = false
            
            let category = UIMutableUserNotificationCategory()
            category.identifier = "YepMessageNotification"
            category.setActions([replyAction, replyOKAction], forContext: UIUserNotificationActionContext.Minimal)
            
            APService.registerForRemoteNotificationTypes(
                UIUserNotificationType.Badge.rawValue |
                    UIUserNotificationType.Sound.rawValue |
                    UIUserNotificationType.Alert.rawValue, categories: [category])
            
        } else {
            
            // 这里才开始向用户提示推送
            APService.registerForRemoteNotificationTypes(
                UIUserNotificationType.Badge.rawValue |
                    UIUserNotificationType.Sound.rawValue |
                    UIUserNotificationType.Alert.rawValue, categories: nil)
        }

        // 预先生成头像和最近消息图片的缓存
        cacheInAdvance()
    }

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "showConversation" {
            let vc = segue.destinationViewController as! ConversationViewController
            vc.conversation = sender as! Conversation
        }
    }

    // MARK: Actions

    func reloadConversationsTableView() {
        dispatch_async(dispatch_get_main_queue()) {
            self.conversationsTableView.reloadData()
        }
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegat

extension ConversationsViewController: UITableViewDataSource, UITableViewDelegate {

    enum Section: Int {

        case FeedConversation
        case Conversation
    }

    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 2
    }

    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case Section.FeedConversation.rawValue:
            return 1
        case Section.Conversation.rawValue:
            return conversations.count
        default:
            return 0
        }
    }

    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {

        switch indexPath.section {

        case Section.FeedConversation.rawValue:
            let cell = tableView.dequeueReusableCellWithIdentifier(feedConversationDockCellID) as! FeedConversationDockCell
            return cell

        case Section.Conversation.rawValue:
            let cell = tableView.dequeueReusableCellWithIdentifier(cellIdentifier) as! ConversationCell

            if let conversation = conversations[safe: indexPath.row] {

                let radius = YepConfig.ConversationCell.avatarSize * 0.5

                cell.configureWithConversation(conversation, avatarRadius: radius, tableView: tableView, indexPath: indexPath)
            }
            
            return cell
            
        default:
            return UITableViewCell()
        }
    }

    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true)

        switch indexPath.section {

        case Section.FeedConversation.rawValue:
            break

        case Section.Conversation.rawValue:
            if let cell = tableView.cellForRowAtIndexPath(indexPath) as? ConversationCell {
                performSegueWithIdentifier("showConversation", sender: cell.conversation)
            }

        default:
            break
        }
    }

    // Edit (for Delete)

    func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {

        if indexPath.section == Section.Conversation.rawValue {
            return true
        }

        return false
    }

    func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {

        if editingStyle == .Delete {

            if let conversation = conversations[safe: indexPath.row] {

                if let realm = conversation.realm {

                    let clearMessages: () -> Void = {

                        let messages = conversation.messages

                        // delete all media files of messages

                        messages.forEach { deleteMediaFilesOfMessage($0) }

                        // delete all mediaMetaDatas

                        for message in messages {
                            if let mediaMetaData = message.mediaMetaData {
                                realm.write {
                                    realm.delete(mediaMetaData)
                                }
                            }
                        }

                        // delete all messages in conversation
                        
                        realm.write {
                            realm.delete(messages)
                        }
                    }

                    let delete: () -> Void = {

                        clearMessages()

                        // delete conversation, finally

                        realm.write {
                            
                            if let group = conversation.withGroup {
                                
                                if let feed = conversation.withGroup?.withFeed {
                                    realm.delete(feed)
                                }
                                
                                let groupID = group.groupID
                                
                                FayeService.sharedManager.unsubscribeGroup(groupID: groupID)
                                
                                leaveGroup(groupID: groupID, failureHandler: { (reason, error) -> Void in
                                    
                                }, completion: { (result) -> Void in
                                    
                                })
                                
                                realm.delete(group)
                                
                            }
                            
                            realm.delete(conversation)
                            
                        }
                    }

                    // show ActionSheet before delete

                    let deleteAlertController = UIAlertController(title: nil, message: nil, preferredStyle: .ActionSheet)

                    let clearHistoryAction: UIAlertAction = UIAlertAction(title: NSLocalizedString("Clear history", comment: ""), style: .Default) { action -> Void in

                        clearMessages()

                        tableView.setEditing(false, animated: true)

                        // update cell
                        
                        if let cell = tableView.cellForRowAtIndexPath(indexPath) as? ConversationCell {
                            if let conversation = self.conversations[safe: indexPath.row] {
                                let radius = min(CGRectGetWidth(cell.avatarImageView.bounds), CGRectGetHeight(cell.avatarImageView.bounds)) * 0.5
                                cell.configureWithConversation(conversation, avatarRadius: radius, tableView: tableView, indexPath: indexPath)
                            }
                        }
                    }
                    deleteAlertController.addAction(clearHistoryAction)

                    let deleteAction: UIAlertAction = UIAlertAction(title: NSLocalizedString("Delete", comment: ""), style: .Destructive) { action -> Void in
                        delete()

                        tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
                    }
                    deleteAlertController.addAction(deleteAction)

                    let cancelAction: UIAlertAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .Cancel) { action -> Void in
                        tableView.setEditing(false, animated: true)
                    }
                    deleteAlertController.addAction(cancelAction)

                    self.presentViewController(deleteAlertController, animated: true, completion: nil)
                }
            }
        }
    }
}


/*
 Copyright (C) 2025 SeanIsTethered

 This file is part of Nyxian.

 FridaCodeManager is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 FridaCodeManager is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with FridaCodeManager. If not, see <https://www.gnu.org/licenses/>.
*/

import Foundation
import UIKit
import Runestone
@testable import Runestone

/*
 * TODO: TodoList for the upcoming changes to the typechecking UI engine
 *
 * - Support to show multiple issues at once
 * - Making save parse in the background to make the app seem faster to the user
 *
 */

// MARK: - COORDINATOR
class Coordinator: NSObject, TextViewDelegate {
    private let parent: CodeEditorViewController
    private var lines: [UInt64] = []
    private var message: [(NeoButton,UIView)] = []
    
    private(set) var isProcessing: Bool = false
    private(set) var isInvalidated: Bool = false
    private(set) var needsAnotherProcess: Bool = false
    
    private let textInputView: TextInputView?
    private let textView: TextView

    private var debounce: Debouncer?
    private(set) var diag: [Synitem] = []
    private let vtkey: [(String,UIColor)] = [
        ("info.circle.fill", UIColor.blue.withAlphaComponent(0.3)),
        ("exclamationmark.triangle.fill", UIColor.orange.withAlphaComponent(0.3)),
        ("xmark.octagon.fill", UIColor.red.withAlphaComponent(0.3))
    ]
    
    init(parent: CodeEditorViewController) {
        self.parent = parent
        self.textView = parent.textView
        self.textInputView = parent.textView.getTextInputView()
        super.init()
        guard self.parent.synpushServer != nil else { return }
        self.debounce = Debouncer(delay: 1.5) {
            self.isProcessing = true
            DispatchQueue.global(qos: .userInitiated).async {
                self.parent.synpushServer!.reparseFile(self.textView.text)
                self.diag = self.parent.synpushServer!.getDiagnostics()
                self.updateDiag()
            }
        }
        self.textViewDidChange(self.parent.textView)
    }
    
    func textViewDidChange(_ textView: TextView) {
        guard self.parent.synpushServer != nil else { return }
        if !self.isInvalidated {
            self.isInvalidated = true
            let copymessage = self.message
            
            for item in copymessage {
                UIView.animate(withDuration: 0.3) {
                    item.1.backgroundColor = UIColor.systemGray.withAlphaComponent(0.3)
                    item.0.backgroundColor = UIColor.systemGray.withAlphaComponent(1.0)
                    item.0.isUserInteractionEnabled = false
                    item.0.errorview?.alpha = 0.0
                } completion: { _ in
                    item.0.errorview?.removeFromSuperview()
                }
            }
        }
        
        if self.isProcessing {
            self.needsAnotherProcess = true
            return
        }
        
        self.debounce?.debounce()
    }
    
    func textViewDidChangeSelection(_ textView: TextView) {
        self.debounce?.debounce()
    }
    
    func updateDiag() {
        let waitonmebaby: DispatchSemaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.3, animations: {
                for item in self.message {
                    item.0.alpha = 0
                    item.1.alpha = 0
                }
            }, completion: { _ in
                for item in self.message {
                    item.0.removeFromSuperview()
                    item.1.removeFromSuperview()
                }
                self.message.removeAll()
                self.lines.removeAll()
                waitonmebaby.signal()
            })
        }
        waitonmebaby.wait()
        
        for item in diag {
            if self.lines.contains(item.line) || (item.line == 0) { continue }
            self.lines.append(item.line)
            
            var rect: CGRect?
            DispatchQueue.main.sync {
                rect = textView.rectForLine(Int(item.line))
            }
            guard let rect = rect else { continue }
            
            let properties: (String,UIColor) = self.vtkey[Int(item.type)]
            
            DispatchQueue.main.async {
                let view: UIView = UIView(frame: CGRect(x: 0, y: rect.origin.y, width: self.textView.bounds.size.width, height: rect.height))
                view.backgroundColor = properties.1
                view.isUserInteractionEnabled = false
                
                let button = NeoButton(frame: CGRect(x: 0, y: rect.origin.y, width: self.parent.textView.gutterWidth, height: rect.height))
                
                button.backgroundColor = properties.1.withAlphaComponent(1.0)
                let configuration: UIImage.SymbolConfiguration = UIImage.SymbolConfiguration(pointSize: self.parent.textView.theme.lineNumberFont.pointSize)
                let image = UIImage(systemName: properties.0, withConfiguration: configuration)
                button.setImage(image, for: .normal)
                button.imageView?.tintColor = UIColor.systemBackground
                
                var widthConstraint: NSLayoutConstraint?
                
                button.setAction {
                    button.stateview = !button.stateview
                    
                    if button.stateview {
                        DispatchQueue.main.async {
                            let shift: CGFloat = self.parent.textView.gutterWidth
                            let finalWidth = self.textView.bounds.width / 1.5
                            
                            let modHeight = rect.height + 10
                            
                            let preview = ErrorPreview(
                                parent: self,
                                frame: CGRect.zero,
                                message: item.message,
                                color: properties.1,
                                minH: modHeight
                            )
                            preview.translatesAutoresizingMaskIntoConstraints = false
                            button.errorview = preview
                            
                            preview.alpha = 0
                            self.textView.addSubview(preview)
                            
                            widthConstraint = preview.widthAnchor.constraint(equalToConstant: 0)
                            NSLayoutConstraint.activate([
                                preview.leadingAnchor.constraint(equalTo: self.textView.leadingAnchor, constant: shift),
                                preview.topAnchor.constraint(equalTo: self.textView.topAnchor, constant: rect.origin.y),
                                widthConstraint!
                            ])
                            
                            self.textView.layoutIfNeeded()
                            
                            UIView.animate(
                                withDuration: 0.5,
                                delay: 0,
                                usingSpringWithDamping: 0.8,
                                initialSpringVelocity: 0.5,
                                options: [.curveEaseOut],
                                animations: {
                                    preview.alpha = 1
                                    widthConstraint!.constant = finalWidth
                                    self.textView.layoutIfNeeded()
                                },
                                completion: nil
                            )
                        }
                    } else {
                        if let preview = button.errorview {
                            DispatchQueue.main.async {
                                UIView.animate(
                                    withDuration: 0.3,
                                    delay: 0,
                                    options: [.curveEaseIn],
                                    animations: {
                                        preview.alpha = 0
                                        widthConstraint!.constant = 0
                                        preview.superview?.layoutIfNeeded()
                                    },
                                    completion: { _ in
                                        preview.removeFromSuperview()
                                    }
                                )
                            }
                        }
                    }
                }
                
                view.alpha = 0
                button.alpha = 0
                self.message.append((button,view))
                
                self.textInputView?.addSubview(view)
                self.textInputView?.sendSubviewToBack(view)
                self.textInputView?.gutterContainerView.isUserInteractionEnabled = true
                self.textInputView?.gutterContainerView.addSubview(button)
                
                UIView.animate(withDuration: 0.3, animations: {
                    view.alpha = 1
                    button.alpha = 1
                }, completion: { _ in
                    button.isUserInteractionEnabled = true
                })
                
            }
        }
        
        DispatchQueue.main.async {
            self.isProcessing = false
            self.isInvalidated = false
            
            if self.needsAnotherProcess {
                self.needsAnotherProcess = false
                self.textViewDidChange(self.parent.textView)
            }
        }
    }
    
    class ErrorPreview: UIView {
        var textView: UITextView
        var heigth: CGFloat = 0.0

        init(parent: Coordinator, frame: CGRect, message: String, color: UIColor, minH: CGFloat) {
            textView = UITextView()
            super.init(frame: .zero)

            self.backgroundColor = parent.parent.textView.theme.gutterBackgroundColor
            self.layer.borderColor = color.withAlphaComponent(1.0).cgColor
            self.layer.borderWidth = 1
            self.layer.cornerRadius = 10
            self.layer.maskedCorners = [
                .layerMaxXMinYCorner,
                .layerMaxXMaxYCorner,
                .layerMinXMaxYCorner
            ]

            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.text = message
            textView.font = parent.parent.textView.theme.font
            textView.font = textView.font?.withSize((textView.font?.pointSize ?? 10) / 1.25)
            textView.textColor = UIColor.label
            textView.backgroundColor = .clear
            textView.isEditable = false
            textView.isScrollEnabled = false
            textView.textContainerInset = UIEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)

            self.addSubview(textView)

            NSLayoutConstraint.activate([
                textView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8),
                textView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
                textView.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
                textView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8),
                self.heightAnchor.constraint(greaterThanOrEqualToConstant: minH)
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    class NeoButton: UIButton {
        var actionTap: () -> Void
        var stateview: Bool = false
        var errorview: ErrorPreview? = nil
        
        let hitTestEdgeInsets = UIEdgeInsets(top: -10, left: -10, bottom: -10, right: -10)
        
        override init(frame: CGRect) {
            self.actionTap = {}
            super.init(frame: frame)
            self.addAction(UIAction { _ in self.actionTap() }, for: UIControl.Event.touchDown)
        }
        
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            let relativeFrame = self.bounds
            let hitFrame = relativeFrame.inset(by: hitTestEdgeInsets)
            return hitFrame.contains(point)
        }
        
        func setAction(action: @escaping () -> Void) {
            self.actionTap = action
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func willMove(toSuperview newSuperview: UIView?) {
            if newSuperview == nil {
                if self.stateview {
                    actionTap()
                }
            }
            super.willMove(toSuperview: newSuperview)
        }
    }
    
    class Debouncer {
        private var workItem: DispatchWorkItem?
        private let queue: DispatchQueue
        private let delay: TimeInterval
        private let action: () -> Void

        init(delay: TimeInterval,
             queue: DispatchQueue = .main,
             action: @escaping () -> Void) {
            self.delay = delay
            self.queue = queue
            self.action = action
        }

        func debounce() {
            workItem?.cancel()
            workItem = DispatchWorkItem(block: action)
            if let workItem = workItem {
                queue.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
        }
    }
}

// MARK: - Test
extension Runestone.TextView {
    func rectForLine(_ lineNumber: Int) -> CGRect? {
        let mirror = Mirror(reflecting: self)
        guard let lmAny = mirror.descendant("textInputView", "layoutManager"),
              let layoutManager = lmAny as? LayoutManager
        else {
            return nil
        }
        
        let lmMirror = Mirror(reflecting: layoutManager)
        guard let lineManager = lmMirror.descendant("lineManager") as? LineManager
        else {
            return nil
        }
        
        let index = lineNumber - 1
        guard index >= 0,
              index < lineManager.lineCount
        else {
            return nil
        }
        
        let targetLine = lineManager.line(atRow: lineNumber - 1)
        let endOffset = targetLine.location + targetLine.data.length
        layoutManager.layoutLines(toLocation: endOffset)
        
        let line = lineManager.line(atRow: index)
        
        let minY = line.yPosition
        let height = line.data.lineHeight
        let inset = layoutManager.textContainerInset
        let width = layoutManager.scrollViewWidth
        
        return CGRect(x: 0,
                      y: inset.top + minY,
                      width: width,
                      height: height)
    }
    
    func getTextInputView() -> TextInputView? {
        let mirror = Mirror(reflecting: self)
        guard let tiview = mirror.descendant("textInputView"),
              let textInputView = tiview as? TextInputView
        else {
            return nil
        }
        
        return textInputView
    }
}

import UIKit

final class CanvasLoadingOverlayView: UIView {
    private let dimView = UIView()
    private let cardView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        alpha = 0

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.24)
        addSubview(dimView)

        cardView.layer.cornerRadius = 26
        cardView.layer.cornerCurve = .continuous
        cardView.clipsToBounds = true
        addSubview(cardView)

        activityIndicator.color = .white
        activityIndicator.startAnimating()
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        cardView.contentView.addSubview(activityIndicator)
        cardView.contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            activityIndicator.topAnchor.constraint(equalTo: cardView.contentView.topAnchor, constant: 24),
            activityIndicator.centerXAnchor.constraint(equalTo: cardView.contentView.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.contentView.trailingAnchor, constant: -20),
            titleLabel.bottomAnchor.constraint(equalTo: cardView.contentView.bottomAnchor, constant: -24)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dimView.frame = bounds
        let cardSize = CGSize(width: min(bounds.width - 48, 240), height: 140)
        cardView.frame = CGRect(
            x: (bounds.width - cardSize.width) / 2,
            y: (bounds.height - cardSize.height) / 2,
            width: cardSize.width,
            height: cardSize.height
        )
    }

    func show(message: String, animated: Bool) {
        titleLabel.text = message
        guard isHidden || alpha < 1 else {
            return
        }

        isHidden = false
        let changes = {
            self.alpha = 1
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: changes)
        } else {
            changes()
        }
    }

    func hide(animated: Bool) {
        guard !isHidden else {
            return
        }

        let finish = {
            self.alpha = 0
        }

        let completion: (Bool) -> Void = { _ in
            self.isHidden = true
        }

        if animated {
            UIView.animate(withDuration: 0.2, animations: finish, completion: completion)
        } else {
            finish()
            completion(true)
        }
    }
}

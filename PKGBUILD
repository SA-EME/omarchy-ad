pkgname=omarchy-ad
pkgver=0.1.0
pkgrel=4
pkgdesc='Active Directory join and multi-user login screen for Omarchy'
arch=('any')
license=('MIT')
depends=('bash' 'sssd' 'krb5' 'samba' 'realmd' 'adcli' 'sudo' 'polkit' 'sddm' 'omarchy')
source=('omarchy-setup-ad'
        'known-users'
        'omarchy-ad-known-users.path'
        'omarchy-ad-known-users.service'
        'omarchy-ad-reapply.path'
        'omarchy-ad-reapply.service'
        'omarchy-ad.hook'
        'LICENSE'
        'Main.qml'
        'user.png'
        'Users.js')
sha256sums=('SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP')

package() {
  cd "$srcdir"
  install -Dm755 omarchy-setup-ad "$pkgdir/usr/bin/omarchy-setup-ad"
  install -Dm755 known-users "$pkgdir/usr/lib/omarchy-ad/known-users"
  install -Dm644 Main.qml user.png Users.js -t "$pkgdir/usr/share/omarchy-ad/theme"
  install -Dm644 omarchy-ad-known-users.path omarchy-ad-known-users.service \
    omarchy-ad-reapply.path omarchy-ad-reapply.service -t "$pkgdir/usr/lib/systemd/system"
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
  install -Dm644 omarchy-ad.hook "$pkgdir/usr/share/libalpm/hooks/90-omarchy-ad.hook"
}

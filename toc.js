// Populate the sidebar
//
// This is a script, and not included directly in the page, to control the total size of the book.
// The TOC contains an entry for each page, so if each page includes a copy of the TOC,
// the total size of the page becomes O(n**2).
class MDBookSidebarScrollbox extends HTMLElement {
    constructor() {
        super();
    }
    connectedCallback() {
        this.innerHTML = '<ol class="chapter"><li class="chapter-item affix "><a href="introduction.html">Introduction</a></li><li class="chapter-item affix "><a href="quick-start.html">Quick start</a></li><li class="chapter-item affix "><li class="spacer"></li><li class="chapter-item "><a href="components.html"><strong aria-hidden="true">1.</strong> Components</a><a class="toggle"><div>❱</div></a></li><li><ol class="section"><li class="chapter-item "><a href="components/pull-through.html"><strong aria-hidden="true">1.1.</strong> Pull-through</a></li><li class="chapter-item "><a href="components/multipass.html"><strong aria-hidden="true">1.2.</strong> Multipass</a></li><li class="chapter-item "><a href="components/hypervisor.html"><strong aria-hidden="true">1.3.</strong> Hypervisor</a></li><li class="chapter-item "><a href="components/cloud-init.html"><strong aria-hidden="true">1.4.</strong> Cloud-init</a></li><li class="chapter-item "><a href="components/k3s.html"><strong aria-hidden="true">1.5.</strong> k3s</a></li><li class="chapter-item "><a href="components/cilium.html"><strong aria-hidden="true">1.6.</strong> Cilium</a></li><li class="chapter-item "><a href="components/argocd.html"><strong aria-hidden="true">1.7.</strong> ArgoCD</a></li><li class="chapter-item "><a href="components/coredns.html"><strong aria-hidden="true">1.8.</strong> CoreDNS</a></li><li class="chapter-item "><a href="components/vault.html"><strong aria-hidden="true">1.9.</strong> Vault</a></li><li class="chapter-item "><a href="components/cert-manager.html"><strong aria-hidden="true">1.10.</strong> cert-manager</a></li><li class="chapter-item "><a href="components/istio.html"><strong aria-hidden="true">1.11.</strong> Istio</a></li><li class="chapter-item "><a href="components/klipper-lb.html"><strong aria-hidden="true">1.12.</strong> klipper-lb</a></li><li class="chapter-item "><a href="components/envoy.html"><strong aria-hidden="true">1.13.</strong> Envoy</a></li></ol></li><li class="chapter-item "><a href="testing.html"><strong aria-hidden="true">2.</strong> Testing</a></li><li class="chapter-item affix "><a href="locality-lb.html">Locality load balancing</a></li><li class="chapter-item affix "><a href="tls.html">TLS</a></li><li class="chapter-item affix "><a href="certificates.html">Certificates</a></li><li class="chapter-item affix "><a href="development.html">Development</a></li><li class="chapter-item affix "><a href="debug.html">Debug</a></li></ol>';
        // Set the current, active page, and reveal it if it's hidden
        let current_page = document.location.href.toString();
        if (current_page.endsWith("/")) {
            current_page += "index.html";
        }
        var links = Array.prototype.slice.call(this.querySelectorAll("a"));
        var l = links.length;
        for (var i = 0; i < l; ++i) {
            var link = links[i];
            var href = link.getAttribute("href");
            if (href && !href.startsWith("#") && !/^(?:[a-z+]+:)?\/\//.test(href)) {
                link.href = path_to_root + href;
            }
            // The "index" page is supposed to alias the first chapter in the book.
            if (link.href === current_page || (i === 0 && path_to_root === "" && current_page.endsWith("/index.html"))) {
                link.classList.add("active");
                var parent = link.parentElement;
                if (parent && parent.classList.contains("chapter-item")) {
                    parent.classList.add("expanded");
                }
                while (parent) {
                    if (parent.tagName === "LI" && parent.previousElementSibling) {
                        if (parent.previousElementSibling.classList.contains("chapter-item")) {
                            parent.previousElementSibling.classList.add("expanded");
                        }
                    }
                    parent = parent.parentElement;
                }
            }
        }
        // Track and set sidebar scroll position
        this.addEventListener('click', function(e) {
            if (e.target.tagName === 'A') {
                sessionStorage.setItem('sidebar-scroll', this.scrollTop);
            }
        }, { passive: true });
        var sidebarScrollTop = sessionStorage.getItem('sidebar-scroll');
        sessionStorage.removeItem('sidebar-scroll');
        if (sidebarScrollTop) {
            // preserve sidebar scroll position when navigating via links within sidebar
            this.scrollTop = sidebarScrollTop;
        } else {
            // scroll sidebar to current active section when navigating via "next/previous chapter" buttons
            var activeSection = document.querySelector('#sidebar .active');
            if (activeSection) {
                activeSection.scrollIntoView({ block: 'center' });
            }
        }
        // Toggle buttons
        var sidebarAnchorToggles = document.querySelectorAll('#sidebar a.toggle');
        function toggleSection(ev) {
            ev.currentTarget.parentElement.classList.toggle('expanded');
        }
        Array.from(sidebarAnchorToggles).forEach(function (el) {
            el.addEventListener('click', toggleSection);
        });
    }
}
window.customElements.define("mdbook-sidebar-scrollbox", MDBookSidebarScrollbox);

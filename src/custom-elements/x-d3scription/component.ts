import d3 from "d3";
import d3scription, { Tip } from "./d3scription";

import * as Utils from "../../utils";

function initObservers() {
    this.tipShown = false;
    this.isOverForbidden = false;
    this.removeObservers = null;

    // @ts-ignore
    const tipFactory = d3scription((msg) => msg, {
        class: "d3scription-tip dashboard-tip" + `${this.darkMode ? " dark-mode" : ""}`
    });

    const content = this.getAttribute("content");
    if (content !== undefined) {
        this.content = content;
    }

    const els = document.querySelectorAll(this.observedSelector);

    const removeObservers = [];

    for (let i = 0; i < els.length; i++) {
        const el = els[i];

        if (!this.tip) {
            this.tip = tipFactory().element(d3.select(el));
        }
        const mouseMoveObserver = (e) => {
            if (this.isOverForbidden) return;

            if (this.tip && !this.tipShown && this.content && d3) {
                // @ts-ignore d3.event is not linked correctly within d3 itself
                d3.event = e;
                this.tip.element(d3.select(el));
                this.tip.show(this.content);
                this.tipShown = true;
            } else if (this.tip && this.tipShown && this.content && d3) {
                this.tip.update(this.content);
            }
        };

        el.addEventListener("mousemove", mouseMoveObserver);
        removeObservers.push(() =>
            el.removeEventListener("mousemove", mouseMoveObserver)
        );

        const mouseOutObserver = (e) => {
            if (this.tip && this.tipShown) {
                this.tip.hide();
                this.tipShown = false;
            }
        };
        el.addEventListener("mouseout", mouseOutObserver);
        removeObservers.push(() => el.removeEventListener("mouseout", mouseOutObserver));
    }

    if (this.forbiddenSelector && document.querySelector(this.forbiddenSelector)) {
        const forbiddenSelectorElement = document.querySelector(this.forbiddenSelector);
        const forbiddenSelectorEvent = () => {
            if (this.tip) {
                this.tip.hide();
                this.tipShown = false;
                this.isOverForbidden = true;
            }
        };
        const forbiddenSelectorOutEvent = () => {
            this.isOverForbidden = false;
        };
        forbiddenSelectorElement.addEventListener("mouseover", forbiddenSelectorEvent);
        forbiddenSelectorElement.addEventListener("mouseout", forbiddenSelectorOutEvent);

        removeObservers.push(() => {
            forbiddenSelectorElement.removeEventListener(
                "mouseover",
                forbiddenSelectorEvent
            );
            forbiddenSelectorElement.removeEventListener(
                "mouseout",
                forbiddenSelectorOutEvent
            );
        });
    }

    this.removeObservers = () => {
        for (const fn of removeObservers) {
            if (typeof fn === "function") {
                fn();
            }
        }
    };
}

/**
 * <x-d3scription target-selector=".my-target" content="<b>Content</b>">
 *   <!-- whatever HTML you put inside -->
 *   <div>
 *     ...
 *     <div class="my-target"> ... </div>
 *     ...
 *   </div>
 * </x-d3scription>
 *
 * will show `content` on hovering over `target-selector` as tooltip
 */
class XD3scription extends HTMLElement {
    static get observedAttributes() {
        return [
            "content",
            "dark-mode",
            "target-selector",
            "forbidden-selector",
            "reinit-trigger"
        ];
    }

    constructor() {
        super();
        this.darkMode = false;
    }

    darkMode: boolean;
    tipShown: boolean;
    isOverForbidden: boolean;
    tip: Tip<string>;
    removeObservers: () => void;
    forbiddenSelector: string;
    observedSelector: string;
    content: string;

    connectedCallback() {
        initObservers.call(this);
    }

    disconnectedCallback() {
        this.tipShown = false;
        this.tip.remove();
        if (this.removeObservers) {
            this.removeObservers();
        }
    }

    attributeChangedCallback(attrName, oldValue: string, newValue) {
        if (attrName === "target-selector" && newValue) {
            this.observedSelector = newValue;
        }

        if (attrName === "content" && newValue) {
            this.content = newValue;
        }

        if (attrName === "dark-mode" && newValue) {
            this.darkMode = newValue;
        }

        if (attrName === "forbidden-selector" && newValue) {
            this.forbiddenSelector = newValue;
        }

        if (attrName === "reinit-trigger" && newValue) {
            if (this.removeObservers) {
                this.removeObservers();
            }
            initObservers.call(this);
        }
    }
}

Utils.register("x-d3scription", XD3scription);

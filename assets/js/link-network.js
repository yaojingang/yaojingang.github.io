(function () {
  "use strict";

  var root = document.querySelector("[data-network]");
  if (!root) return;
  var data = JSON.parse(document.getElementById("link-network-data").textContent);
  var svg = root.querySelector("[data-network-svg]");
  var picker = root.querySelector("[data-network-select]");
  var products = root.querySelector("[data-network-products]");
  var neighbors = root.querySelector("[data-network-neighbors]");
  var nodes = new Map(data.nodes.map(function (node) { return [node.id, node]; }));
  var pairs = new Set(data.links.map(function (link) { return link.source + "|" + link.target; }));
  var selected = data.home;
  var positions = new Map();
  var nodeElements = new Map();
  var edgeElements = [];
  var scale = 1;
  var pan = { x: 0, y: 0 };
  var drag = null;
  var width = 0;
  var height = 0;
  var ns = "http://www.w3.org/2000/svg";

  function element(tag, attrs, text) {
    var el = document.createElementNS(ns, tag);
    Object.keys(attrs || {}).forEach(function (key) { el.setAttribute(key, attrs[key]); });
    if (text !== undefined) el.textContent = text;
    return el;
  }

  function outgoing(id) { return data.links.filter(function (link) { return link.source === id; }); }
  function incoming(id) { return data.links.filter(function (link) { return link.target === id; }); }
  function radius(node) {
    if (node.kind === "product") return 6;
    return 9 + Math.min(10, Math.sqrt(outgoing(node.id).length + incoming(node.id).length) * 1.5);
  }

  function showRelations(direction, links) {
    var list = root.querySelector("[data-network-" + direction + "]");
    var empty = root.querySelector("[data-network-" + direction + "-empty]");
    list.replaceChildren();
    root.querySelector("[data-network-" + direction + "-count]").textContent = links.length;
    links.forEach(function (link) {
      var other = nodes.get(direction === "out" ? link.target : link.source);
      var li = document.createElement("li");
      var button = document.createElement("button");
      button.type = "button";
      button.textContent = other.name;
      button.dataset.nodeRef = other.id;
      var badge = document.createElement("span");
      badge.textContent = pairs.has(link.target + "|" + link.source) ? "互链" : "↗";
      badge.setAttribute("aria-hidden", "true");
      button.appendChild(badge);
      button.addEventListener("click", function () { select(other.id); });
      li.appendChild(button);
      list.appendChild(li);
    });
    empty.hidden = links.length > 0;
    list.hidden = links.length === 0;
  }

  function detail() {
    var node = nodes.get(selected);
    var out = outgoing(selected);
    var into = incoming(selected);
    root.querySelector("[data-network-name]").textContent = node.name;
    root.querySelector("[data-network-domain]").textContent = new URL(node.url).hostname;
    root.querySelector("[data-network-kind]").textContent = node.id === data.home ? "从这里出发" : node.kind === "site" ? "朋友站点" : "朋友的产品";
    root.querySelector("[data-network-visit]").href = node.url;
    root.querySelector("[data-network-summary]").textContent = out.length + " 条出链 · " + into.length + " 条入链";
    root.querySelector("[data-network-out-empty]").textContent = node.collected ? "这次首页快照中暂未发现指向已收录节点的链接。" : "此产品首页的出站链接尚未采集。";
    showRelations("out", out);
    showRelations("in", into);
  }

  function visibleData() {
    var related = new Set([selected]);
    data.links.forEach(function (link) {
      if (link.source === selected) related.add(link.target);
      if (link.target === selected) related.add(link.source);
    });
    var visible = data.nodes.filter(function (node) {
      return (products.checked || node.kind === "site") && (!neighbors.checked || related.has(node.id));
    });
    var ids = new Set(visible.map(function (node) { return node.id; }));
    return { nodes: visible, links: data.links.filter(function (link) { return ids.has(link.source) && ids.has(link.target); }) };
  }

  function ellipse(items, rx, ry, phase) {
    var samples = [{ angle: phase, length: 0 }];
    var total = 0;
    for (var i = 1; i <= 720; i++) {
      var a = phase + (i - 1) * Math.PI / 360;
      var b = phase + i * Math.PI / 360;
      total += Math.hypot(rx * (Math.cos(b) - Math.cos(a)), ry * (Math.sin(b) - Math.sin(a)));
      samples.push({ angle: b, length: total });
    }
    items.forEach(function (node, index) {
      var distance = index * total / items.length;
      var sample = samples.find(function (point) { return point.length >= distance; });
      positions.set(node.id, { x: width / 2 + rx * Math.cos(sample.angle), y: height / 2 + ry * Math.sin(sample.angle) });
    });
  }

  function arrange(visible) {
    positions.clear();
    positions.set(data.home, { x: width / 2, y: height / 2 });
    var sites = visible.filter(function (node) { return node.kind === "site" && node.id !== data.home; });
    var tools = visible.filter(function (node) { return node.kind === "product"; });
    ellipse(sites, width * (tools.length ? 0.25 : 0.34), height * (tools.length ? 0.23 : 0.34), -Math.PI / 2);
    ellipse(tools, width / 2 - 36, height / 2 - 44, -Math.PI / 2 + 0.1);
    for (var pass = 0; pass < 28; pass++) {
      visible.forEach(function (a, index) {
        visible.slice(index + 1).forEach(function (b) {
          var p = positions.get(a.id);
          var q = positions.get(b.id);
          var dx = q.x - p.x;
          var dy = q.y - p.y;
          var distance = Math.hypot(dx, dy) || 1;
          var minimum = Math.max(42, radius(a) + radius(b) + 14);
          if (distance >= minimum) return;
          var shift = (minimum - distance) / 2;
          if (a.id !== data.home) { p.x -= dx / distance * shift; p.y -= dy / distance * shift; }
          if (b.id !== data.home) { q.x += dx / distance * shift; q.y += dy / distance * shift; }
          [p, q].forEach(function (point) {
            point.x = Math.max(24, Math.min(width - 24, point.x));
            point.y = Math.max(30, Math.min(height - 38, point.y));
          });
        });
      });
    }
  }

  function path(link) {
    var a = positions.get(link.source);
    var b = positions.get(link.target);
    var dx = b.x - a.x;
    var dy = b.y - a.y;
    var distance = Math.hypot(dx, dy) || 1;
    var bend = Math.min(30, distance * 0.12);
    var mx = (a.x + b.x) / 2 - dy / distance * bend;
    var my = (a.y + b.y) / 2 + dx / distance * bend;
    var startLength = Math.hypot(mx - a.x, my - a.y) || 1;
    var endLength = Math.hypot(b.x - mx, b.y - my) || 1;
    var r1 = radius(nodes.get(link.source)) + 2;
    var r2 = radius(nodes.get(link.target)) + 9;
    return "M" + (a.x + (mx - a.x) / startLength * r1) + "," + (a.y + (my - a.y) / startLength * r1) + " Q" + mx + "," + my + " " + (b.x - (b.x - mx) / endLength * r2) + "," + (b.y - (b.y - my) / endLength * r2);
  }

  function transform() {
    var layer = svg.querySelector("[data-network-layer]");
    if (layer) layer.setAttribute("transform", "translate(" + pan.x + " " + pan.y + ") scale(" + scale + ")");
    svg.classList.toggle("is-zoomed", scale > 1.3);
  }

  function highlight(hovered) {
    var focus = hovered || selected;
    edgeElements.forEach(function (item) {
      var state = item.link.source === focus ? "outgoing" : item.link.target === focus ? "incoming" : "quiet";
      item.el.setAttribute("class", "network-edge is-" + state);
      item.el.setAttribute("marker-end", "url(#network-arrow-" + state + ")");
    });
    nodeElements.forEach(function (el, id) {
      el.classList.toggle("is-selected", id === selected);
      el.classList.toggle("is-hovered", id === hovered);
      el.setAttribute("aria-pressed", String(id === selected));
    });
  }

  function draw() {
    var focusedNode = document.activeElement.getAttribute("data-node");
    width = svg.clientWidth;
    height = svg.clientHeight;
    if (!width || !height) return;
    scale = 1;
    pan = { x: 0, y: 0 };
    var visible = visibleData();
    arrange(visible.nodes);
    svg.setAttribute("viewBox", "0 0 " + width + " " + height);
    svg.classList.toggle("has-room", width >= 580);
    svg.replaceChildren();
    nodeElements.clear();
    edgeElements = [];
    var defs = element("defs");
    ["quiet", "incoming", "outgoing"].forEach(function (state) {
      var marker = element("marker", { id: "network-arrow-" + state, viewBox: "0 0 8 8", refX: 7, refY: 4, markerWidth: 6, markerHeight: 6, orient: "auto", markerUnits: "userSpaceOnUse" });
      marker.appendChild(element("path", { d: "M0,0 L8,4 L0,8 Z", "class": "network-arrow is-" + state }));
      defs.appendChild(marker);
    });
    svg.appendChild(defs);
    var layer = element("g", { "data-network-layer": "" });
    visible.links.forEach(function (link) {
      var el = element("path", { d: path(link), "data-source": link.source, "data-target": link.target });
      layer.appendChild(el);
      edgeElements.push({ el: el, link: link });
    });
    visible.nodes.forEach(function (node) {
      var point = positions.get(node.id);
      var r = radius(node);
      var el = element("g", { "class": "network-node is-" + node.kind, transform: "translate(" + point.x + " " + point.y + ")", role: "button", tabindex: "0", "aria-label": node.name + "，查看链接关系", "data-node": node.id });
      el.appendChild(element("title", {}, node.name + " · " + new URL(node.url).hostname));
      el.appendChild(element("circle", { r: Math.max(20, r + 5), "class": "network-node-hit" }));
      el.appendChild(element("circle", { r: r, "class": "network-node-dot" }));
      if (node.kind === "site") el.appendChild(element("text", { y: 4, "text-anchor": "middle", "class": "network-node-initial" }, node.id === data.home ? "YAO" : node.label.charAt(0)));
      var anchor = point.x < 90 ? "start" : point.x > width - 90 ? "end" : "middle";
      el.appendChild(element("text", { x: anchor === "start" ? -r : anchor === "end" ? r : 0, y: r + 18, "text-anchor": anchor, "class": "network-node-label" }, node.label));
      el.addEventListener("click", function () { select(node.id); });
      el.addEventListener("keydown", function (event) {
        if (event.key === "Enter" || event.key === " ") { event.preventDefault(); select(node.id); }
      });
      el.addEventListener("pointerenter", function (event) { if (event.pointerType === "mouse") highlight(node.id); });
      el.addEventListener("pointerleave", function () { highlight(); });
      el.addEventListener("focus", function () { ensureVisible(node.id); highlight(node.id); });
      el.addEventListener("blur", function () { highlight(); });
      layer.appendChild(el);
      nodeElements.set(node.id, el);
    });
    svg.appendChild(layer);
    transform();
    highlight();
    if (focusedNode && nodeElements.has(focusedNode)) nodeElements.get(focusedNode).focus({ preventScroll: true });
  }

  function ensureVisible(id) {
    var point = positions.get(id);
    if (point && (point.x * scale + pan.x < 24 || point.x * scale + pan.x > width - 24 || point.y * scale + pan.y < 24 || point.y * scale + pan.y > height - 24)) {
      pan = { x: width / 2 - point.x * scale, y: height / 2 - point.y * scale };
      transform();
    }
  }

  function select(id) {
    if (!nodes.has(id)) return;
    var retainFocus = svg.contains(document.activeElement) || document.activeElement.hasAttribute("data-node-ref");
    selected = id;
    picker.value = id;
    var wasHidden = nodes.get(id).kind === "product" && !products.checked;
    if (wasHidden) products.checked = true;
    if (neighbors.checked || wasHidden) draw();
    detail();
    highlight();
    ensureVisible(id);
    if (retainFocus && nodeElements.has(id)) nodeElements.get(id).focus({ preventScroll: true });
  }

  function zoom(factor) {
    var next = Math.max(0.65, Math.min(2.5, scale * factor));
    pan.x = width / 2 - (width / 2 - pan.x) * next / scale;
    pan.y = height / 2 - (height / 2 - pan.y) * next / scale;
    scale = next;
    transform();
  }

  picker.addEventListener("change", function () { select(picker.value); });
  products.addEventListener("change", function () {
    if (!products.checked && nodes.get(selected).kind === "product") select(data.home);
    draw();
  });
  neighbors.addEventListener("change", draw);
  root.querySelectorAll("[data-network-zoom]").forEach(function (button) {
    button.addEventListener("click", function () {
      if (button.dataset.networkZoom === "reset") { scale = 1; pan = { x: 0, y: 0 }; transform(); }
      else zoom(button.dataset.networkZoom === "in" ? 1.2 : 1 / 1.2);
    });
  });
  svg.addEventListener("pointerdown", function (event) {
    if (drag || event.button !== 0 || event.target.closest("[data-node]")) return;
    drag = { id: event.pointerId, x: event.clientX, y: event.clientY, panX: pan.x, panY: pan.y };
    svg.setPointerCapture(event.pointerId);
    svg.classList.add("is-dragging");
  });
  svg.addEventListener("pointermove", function (event) {
    if (!drag || drag.id !== event.pointerId) return;
    pan = { x: drag.panX + event.clientX - drag.x, y: drag.panY + event.clientY - drag.y };
    transform();
  });
  ["pointerup", "pointercancel", "lostpointercapture"].forEach(function (name) {
    svg.addEventListener(name, function (event) {
      if (!drag || drag.id !== event.pointerId) return;
      drag = null;
      svg.classList.remove("is-dragging");
    });
  });
  new ResizeObserver(draw).observe(svg);
  detail();
  draw();
})();

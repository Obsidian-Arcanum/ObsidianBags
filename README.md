<p align="center">
  <img src="images/banner.png" alt="Obsidian Bags — Designed with your play style in mind." width="850">
</p>

<h1 align="center">Obsidian Bags</h1>

<p align="center"><strong>Designed with your play style in mind.</strong></p>

<p align="center">
  <a href="https://www.curseforge.com/wow/addons/obsidian-bags">CurseForge</a>
  &nbsp;·&nbsp;
  <a href="https://github.com/Obsidian-Arcanum/ObsidianBags/issues">Report a Bug / Request a Feature</a>
  &nbsp;·&nbsp;
  <a href="https://github.com/Obsidian-Arcanum">Obsidian Arcanum</a>
</p>

---

## Your Inventory. Your Way.

Your bags should fit the way you play, not ask you to change the way you play.

**Obsidian Bags** is a customizable inventory addon designed for **World of Warcraft Forever**, built around a simple idea: **your inventory should adapt to you, not the other way around.** Keep everything together in a familiar, unified view or arrange items into detailed, personalized categories. Choose an ornate fantasy interface or a clean, minimalist one. Adjust as much or as little as you like.

**Simple when you want it. Flexible when you need it.**

## Two Ways to Organize

### Standard View: Everything in One Place

Prefer a traditional inventory? **Standard View** keeps your items together in a unified window for quick access. Adjust the layout and expand or collapse supported sections to display only the slots you need.

<p align="center">
  <img src="images/standard-fancy-collapsed.png" alt="Standard View in the Fancy theme with compact sections" width="519">
</p>

<details>
<summary><strong>See Standard View with inventory sections expanded</strong></summary>

<br>
<p align="center">
  <img src="images/standard-fancy-expanded.png" alt="Standard View with expanded inventory, arrow, and reagent sections" width="519">
</p>

</details>

### Category View: Organization on Your Terms

Want more structure? **Category View** organizes items into configurable, named categories. Position categories across columns, rearrange their order, and collapse individual sections when you want a more compact window.

<p align="center">
  <img src="images/category-fancy-collapsed.png" alt="Category View in the Fancy theme with multiple organized categories" width="626">
</p>

<details>
<summary><strong>See Category View with additional sections expanded</strong></summary>

<br>
<p align="center">
  <img src="images/category-fancy-expanded.png" alt="Category View with crafting materials, utility, and available-slot sections expanded" width="631">
</p>

</details>

Both views use the same underlying inventory system. Neither requires sacrificing functionality for your preferred arrangement.

## Customization Without Complexity

Powerful customization should feel natural, not like a second project.

- **Create and manage your own categories** for the items you care about.
- **Drag items into categories** to assign them, or enter comma-separated item IDs for precise assignments.
- **Rearrange category positions and columns** to build the layout you want.
- **Adjust inventory dimensions and section presentation** to match your available screen space.
- **Expand and collapse sections** as your needs change.
- **Customize through the in-game settings panel**, with configuration preferences and profiles.

Start with the defaults and change only what matters to you.

## Two Distinct Themes

Choose the presentation that feels right for your screen. **Both themes provide the same core inventory functionality.**

- **Fancy (default)** is the Obsidian Arcanum signature: gold framing, glowing blue arcane accents, decorative artwork, and illustrated controls.
- **Basic** takes a minimalist approach with simpler buttons, restrained framing, and adjustable background opacity.

| Fancy | Basic |
| :---: | :---: |
| <img src="images/category-fancy-collapsed.png" alt="Fancy theme with ornate gold-and-arcane styling" width="390"> | <img src="images/category-basic-collapsed.png" alt="Basic theme with minimalist controls" width="390"> |

## Intelligent Inventory Optimization

Obsidian Bags separates **how your inventory is displayed** from **where items are physically stored**. Its sorting system focuses on useful storage improvements rather than moving every item to imitate an on-screen arrangement.

- Consolidates compatible partial item stacks.
- Respects supported specialized bags and item placement rules.
- Avoids unnecessary physical item movements.
- Spreads sorting work across multiple game frames to reduce interruptions.

Use the **Sort** control whenever you want. Optional **sort on bag open** is available in settings and is **disabled by default**.

## Effortless Junk Management

### Mark it. Forget it. Get paid.

**Alt-click** an unwanted item to mark it for sale. The next time you visit a vendor, Obsidian Bags automatically sells eligible marked items so you don't need to find and click through them individually.

<p align="center">
  <img src="images/junk-category.png" alt="Junk category with marked SELL items" width="261">
  &nbsp;&nbsp;
  <img src="images/sell-preview.png" alt="Item slots with visible SELL markers" width="194">
</p>

## More Ways to Manage Your Items

**One Stack presentation** offers a compact way to represent stacks, with a pop-out for inspecting the items behind that summary when needed. Specialized sections help distinguish applicable ammunition, reagents, and other storage.

**Bank management** follows the same philosophy as your carried inventory, including organized views and tools for working with stored items. Obsidian Bags has dedicated bank interfaces and supports item transfers when the relevant in-game storage is available.

As with ordinary inventory interactions, actual item transfers are subject to the game's normal rules and restrictions.

## Inventory Memory & Syndicator Integration

**[Syndicator](https://www.curseforge.com/wow/addons/syndicator) is a required dependency.** It provides essential data used by Obsidian Bags, including support for remembered bags and bank contents from other characters.

You can inspect previously recorded inventory information without switching characters just to check what Syndicator remembers. **Remembered inventory is cached information, not live access to another character's bags.**

Syndicator also provides item data used by other inventory-management features. **It must be installed separately** using a build compatible with World of Warcraft Forever.

## Installation & Requirements

| Requirement | Details |
| --- | --- |
| Supported game | **World of Warcraft Forever** |
| Required addon | **[Syndicator](https://www.curseforge.com/wow/addons/syndicator)** (Forever-compatible version) |
| Other WoW versions | Retail, Classic, and Classic Era are **not officially supported or tested** |

### Install through CurseForge

1. Visit the **[Obsidian Bags CurseForge project](https://www.curseforge.com/wow/addons/obsidian-bags)** and select a compatible published release when available.
2. Install it through the CurseForge app, if the client supports your WoW Forever installation.
3. Confirm that a compatible **Syndicator** version is also installed and enabled. CurseForge normally handles declared required dependencies, but compatibility should still be checked.
4. Start the game or run `/reload` if already in-game.

### Manual installation

1. Download a released **Obsidian Bags ZIP** and a **World of Warcraft Forever-compatible Syndicator** release.
2. Extract the addon folders into your WoW Forever installation's `Interface/AddOns/` directory.
3. Ensure that `ObsidianBags.toc` is directly inside `Interface/AddOns/ObsidianBags/`, not inside a second nested folder.
4. Enable **both** Obsidian Bags and Syndicator, then restart the game or type `/reload`.

Example folder layout:

```text
Interface/
└── AddOns/
    ├── ObsidianBags/
    │   ├── ObsidianBags.toc
    │   ├── Core.lua
    │   ├── Media/
    │   └── ...
    └── Syndicator/
        ├── Syndicator.toc
        └── ...
```

**Note:** The GitHub repository contains source files and project imagery. For installation, use a published addon ZIP rather than GitHub's automatically generated "Download ZIP" source archive.

## Configuration

Open the Obsidian Bags settings using the **cog at the upper-right corner** of the inventory window, or type `/obags` or `/obsidianbags` in chat.

The settings interface provides layout, category, appearance, sorting, and other supported preferences. The same cog is available with either theme.

## Support & Development

Found a bug or have an idea? Please use **[GitHub Issues](https://github.com/Obsidian-Arcanum/ObsidianBags/issues)** for reports, feature requests, and feedback. When reporting a problem, include the addon version, the steps that reproduce it, what you expected, and what happened instead.

- **[CurseForge project](https://www.curseforge.com/wow/addons/obsidian-bags)** for the published addon and releases.
- **[Source repository](https://github.com/Obsidian-Arcanum/ObsidianBags)** for the code and project history.
- **[Syndicator](https://www.curseforge.com/wow/addons/syndicator)** by plusmouse, a separately maintained required dependency.

This project is distributed under the terms of its [LICENSE](LICENSE) file.

---

<p align="center">
  <a href="https://github.com/Obsidian-Arcanum">
    <img src="https://github.com/Obsidian-Arcanum.png" alt="Obsidian Arcanum emblem" width="260">
  </a>
</p>

<p align="center"><strong><a href="https://github.com/Obsidian-Arcanum">An Obsidian Arcanum Project</a></strong></p>

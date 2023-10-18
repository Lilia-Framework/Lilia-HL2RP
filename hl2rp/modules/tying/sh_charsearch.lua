local PLUGIN = PLUGIN

if (SERVER) then
	function PLUGIN:ns1SetupInventorySearch(client, target)
		local inventory = target:getChar():getInv(client, target)

		-- Permit the player to move items from their inventory to the target's inventory.
		inventory.oldOnAuthorizeTransfer = inventory.onAuthorizeTransfer
		inventory.onAuthorizeTransfer = function(inventory, client2, oldInventory, item)
			if (IsValid(client2) and client2 == client) then
				return true
			end

			return false
		end
		inventory:sync(client)
		inventory.oldGetReceiver = inventory.getReceiver
		inventory.getReceiver = function(inventory)
			return {client, target}
		end
		inventory.onCheckAccess = function(inventory, client2)
			if (client2 == client) then
				return true
			end
		end

		-- Permit the player to move items from the target's inventory back into their inventory.
		local inventory2 = client:getChar():getInv()
		inventory2.oldOnAuthorizeTransfer = inventory2.onAuthorizeTransfer
		inventory2.onAuthorizeTransfer = function(inventory3, client2, oldInventory, item)
			if (oldInventory == inventory) then
				return true
			end

			return inventory2.oldOnAuthorizeTransfer(inventory3, client2, oldInventory, item)
		end
	end

	function PLUGIN:ns1RemoveInventorySearchPermissions(client, target)
		local inventory = target:getChar():getInv()
		inventory.onAuthorizeTransfer = inventory.oldOnAuthorizeTransfer
		inventory.oldOnAuthorizeTransfer = nil
		inventory.getReceiver = inventory.oldGetReceiver
		inventory.oldGetReceiver = nil
		inventory.onCheckAccess = nil
			
		local inventory2 = client:getChar():getInv()
		inventory2.onAuthorizeTransfer = inventory2.oldOnAuthorizeTransfer
		inventory2.oldOnAuthorizeTransfer = nil
	end

	function PLUGIN:ns2SetupInventorySearch(client, target)
		local function searcherCanAccess(inventory, action, context)
			if (context.client == client) then
				return true
			end
		end

		target:getChar():getInv():addAccessRule(searcherCanAccess)
		target.liaSearchAccessRule = searcherCanAccess

		target:getChar():getInv():sync(client)
	end

	function PLUGIN:ns2RemoveInventorySearchPermissions(client, target)
		local rule = target.liaSearchAccessRule
		if (rule) then
			target:getChar():getInv():removeAccessRule(rule)
		end
	end

	function PLUGIN:searchPlayer(client, target)
		if (IsValid(target:getNetVar("searcher")) or IsValid(client.liaSearchTarget)) then
			client:notifyLocalized("This person is already being searched.")
			return false
		end

		if (!target:getChar() or !target:getChar():getInv()) then
			client:notifyLocalized("invalidPly")
			return false
		end

		if (lia.version) then
			self:ns2SetupInventorySearch(client, target)
		else
			self:ns1SetupInventorySearch(client, target)
		end

		-- Show the inventory menu to the searcher.
		netstream.Start(client, "searchPly", target, target:getChar():getInv():getID())

		client.liaSearchTarget = target
		target:setNetVar("searcher", client)

		return true
	end

	function PLUGIN:CanPlayerInteractItem(client, action, item)
		if (IsValid(client:getNetVar("searcher"))) then
			return false
		end
	end

	function PLUGIN:stopSearching(client)
		local target = client.liaSearchTarget

		if (IsValid(target) and target:getNetVar("searcher") == client) then
			if (lia.version) then
				PLUGIN:ns2RemoveInventorySearchPermissions(client, target)
			else
				PLUGIN:ns1RemoveInventorySearchPermissions(client, target)
			end

			target:setNetVar("searcher", nil)
			client.liaSearchTarget = nil

			netstream.Start(client, "searchExit")
		end
	end

	netstream.Hook("searchExit", function(client)
		PLUGIN:stopSearching(client)
	end)
else
	PLUGIN.searchPanels = PLUGIN.searchPanels or {}

	function PLUGIN:CanPlayerViewInventory()
		if (IsValid(LocalPlayer():getNetVar("searcher"))) then
			return false
		end
	end

	if (lia.version) then
		netstream.Hook("searchPly", function(target, id)
			local targetInv = lia.inventory.instances[id]
			if (not targetInv) then
				return netstream.Start("searchExit")
			end

			local myInvPanel, targetInvPanel
			local exitLock = true
			local function onRemove(panel)
				local other = panel == myInvPanel and targetInvPanel
					or myInvPanel
				if (IsValid(other) and exitLock) then
					exitLock = false
					other:Remove()
				end

				netstream.Start("searchExit")
				panel:searchOnRemove()
			end

			myInvPanel = LocalPlayer():getChar():getInv():show()
			myInvPanel:ShowCloseButton(true)
			myInvPanel.searchOnRemove = myInvPanel.OnRemove
			myInvPanel.OnRemove = onRemove

			targetInvPanel = targetInv:show()
			targetInvPanel:ShowCloseButton(true)
			targetInvPanel:SetTitle(target:Name())
			targetInvPanel.searchOnRemove = targetInvPanel.OnRemove
			targetInvPanel.OnRemove = onRemove

			myInvPanel.x = myInvPanel.x + (myInvPanel:GetWide() * 0.5) + 2
			targetInvPanel:MoveLeftOf(myInvPanel, 4)

			PLUGIN.searchPanels[#PLUGIN.searchPanels + 1] = myInvPanel
			PLUGIN.searchPanels[#PLUGIN.searchPanels + 1] = targetInvPanel
		end)
	else
		netstream.Hook("searchPly", function(target, index)
			local inventory = lia.item.inventories[index]

			if (!inventory) then
				return netstream.Start("searchExit")
			end

			lia.gui.inv1 = vgui.Create("liaInventory")
			lia.gui.inv1:ShowCloseButton(true)
			lia.gui.inv1:setInventory(LocalPlayer():getChar():getInv())

			PLUGIN.searchPanels[#PLUGIN.searchPanels + 1] = lia.gui.inv1

			local panel = vgui.Create("liaInventory")
			panel:ShowCloseButton(true)
			panel:SetTitle(target:Name())
			panel:setInventory(inventory)
			panel:MoveLeftOf(lia.gui.inv1, 4)
			panel.OnClose = function(this)
				if (IsValid(lia.gui.inv1) and !IsValid(lia.gui.menu)) then
					lia.gui.inv1:Remove()
				end

				netstream.Start("searchExit")
			end

			local oldClose = lia.gui.inv1.OnClose
			lia.gui.inv1.OnClose = function()
				if (IsValid(panel) and !IsValid(lia.gui.menu)) then
					panel:Remove()
				end

				netstream.Start("searchExit")
				lia.gui.inv1.OnClose = oldClose
			end

			lia.gui["inv"..index] = panel	
			PLUGIN.searchPanels[#PLUGIN.searchPanels + 1] = panel
		end)
	end

	netstream.Hook("searchExit", function()
		for _, panel in pairs(PLUGIN.searchPanels) do
			if (IsValid(panel)) then
				panel:Remove()
			end
		end
		PLUGIN.searchPanels = {}
	end)
end

lia.command.add("charsearch", {
	onRun = function(client, arguments)
		local data = {}
			data.start = client:GetShootPos()
			data.endpos = data.start + client:GetAimVector()*96
			data.filter = client
		local target = util.TraceLine(data).Entity

		if (not client:getChar() or not client:getChar():getInv()) then
			return false
		end

		if (not IsValid(target) or not target:IsPlayer()) then
			return false, "@invalidPly"
		end

		if (target:getNetVar("restricted")) then
			PLUGIN:searchPlayer(client, target)
		else
			return false, "@This player must be tied"
		end
	end
})
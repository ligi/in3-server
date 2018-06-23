pragma solidity ^0.4.19;

/// @title Registry for IN§-Nodes
contract ServerRegistry {

    uint internal constant unregisterDeposit = 100000;

    event LogServerRegistered(string url, uint props, address owner, uint deposit);
    event LogServerUnregisterRequested(string url, address owner, address caller);
    event LogServerUnregisterCanceled(string url, address owner);
    event LogServerConvicted(string url, address owner);
    event LogServerRemoved(string url, address owner);

    struct Web3Server {
        string url;  // the url of the server
        uint deposit; // stored deposit
        uint props; // a list of properties-flags representing the capabilities of the server
        uint index; // index in serverAddresses
        // unregister state
        uint unregisterTime; // earliest timestamp in to to call unregister
        address unregisterCaller; // address of the caller requesting the unregister
    }

    mapping(address => Web3Server) servers;
    address[] serverAddresses;

    /// register a new Server with the sender as owner    
    function registerServer(string _url, uint _props) public payable {
        // make sure this this owner was not registered before.
        require (servers[msg.sender].url[0] == 0);
        
        // create new Webserver
        Web3Server memory m;
        m.url = _url;
        m.props = _props;
        m.index = serverAddresses.length;
        m.deposit = msg.value;
        servers[msg.sender] = m;
        serverAddresses.push(msg.sender);
        totalDeposit += msg.value;
        LogServerRegistered(_url, _props, msg.sender,msg.value);
    }

    /// this should be called before unregistering a server.
    /// there are 2 use cases:
    /// a) the owner wants to stop offering this.
    ///    in this case he has to wait for one hour before actually removing the server.
    ///    This is needed in order to give others a chance to convict it in case this server signs wrong hashes
    /// b) anybody can request to remove a server because it has been inactive.
    ///    in this case he needs to pay a small deposit, which he will lose 
    //       if the owner become active again 
    //       or the caller will receive 20% of the deposit in case the owner does not react.
    function requestUnregisteringServer(address _owner) payable public {
        var server = servers[_owner];
        // this can only be called if nobody requested it before
        require(server.unregisterCaller==address(0x0));

        if (server.unregisterCaller == _owner) 
           server.unregisterTime = now + 1 hours;
        else {
            server.unregisterTime = now + 28 days; // 28 days are always good ;-) 
            // the requester needs to pay the unregisterDeposit in order to spam-protect the server
            require(msg.value==unregisterDeposit);
        }
        server.unregisterCaller = msg.sender;
        LogServerUnregisterRequested(server.url, _owner, msg.sender );
    }
    
    function confirmUnregisteringServer(address _owner) public {
        var server = servers[_owner];
        // this can only be called if somebody requested it before
        require(server.unregisterCaller!=address(0x0) && server.unregisterTime < now);

        var payBackOwner = server.deposit;
        if (server.unregisterCaller != _owner) {
            payBackOwner -= server.deposit/5;  // the owner will only receive 80% of his deposit back.
            server.unregisterCaller.transfer( unregisterDeposit + server.deposit - payBackOwner );
        }

        if (payBackOwner>0)
            _owner.transfer( payBackOwner );

        removeServer(_owner);
    }

    function cancelUnregisteringServer(address _owner) public {
        var server = servers[_owner];

        // this can only be called by the owner and if somebody requested it before
        require(server.unregisterCaller != address(0) && _owner == msg.sender);

        // if this was requested by somebody who does not own this server,
        // the owner will get his deposit
        if (server.unregisterCaller != _owner) 
            _owner.transfer( unregisterDeposit );

        server.unregisterCaller = address(0);
        server.unregisterTime = 0;
        
        LogServerUnregisterCanceled(server.url, _owner);
    }


    function convict(address _owner, bytes32 _blockhash, uint _blocknumber, uint8 _v, bytes32 _r, bytes32 _s) public {
        // if the blockhash is correct you cannot convict the server
        require(block.blockhash(_blocknumber) != _blockhash);

        // make sure the hash was signed by the owner of the server
        require(ecrecover(keccak256(_blockhash, _blocknumber), _v, _r, _s) == _owner);

        // remove the deposit
        if (servers[_owner].deposit>0) {
            var payout = servers[_owner].deposit/2;
            // send 50% to the caller of this function
            msg.sender.transfer(payout);

            // and burn the rest by sending it to the 0x0-address
            address(0).transfer(servers[_owner].deposit-payout);
        }

        LogServerConvicted(servers[_owner].url, _owner );
        removeServer(_owner);

    }
    
    // internal helpers
    
    function removeServer(address _owner) internal {
        address lastServer = serverAddresses[serverAddresses.length - 1];
        serverAddresses[servers[_owner].index] = lastServer;
        totalDeposit -= servers[_owner].deposit;
        LogServerRemoved(servers[_owner].url, _owner);
        Web3Server memory m;
        servers[_owner] = m;
    }




    // payment

    struct Claim {
        address server;
        uint startDepositClaim;
    }
    
    struct Client {
        uint deposit;
        uint winningNumber;
        Claim server; // between 0 and totalDeposit
    }

    mapping (address => Client) clients;
    uint totalDeposit;
    mapping(address => uint) claimLoopIndex;
    uint constant MINITERATIONGAS = 10000; // TO Be Checked
    
    function registerClient(uint _endLottery) public payable {
        Client memory c;
        c.deposit = msg.value;
        c.endLottery = _endLottery;
        clients[msg.sender]=c;
    }
    
    function claimWinningTicket(uint _nonce, uint _nonceMax, address _server, address _client, uint _startDepositClaim, uint8 _v, bytes32 _r, bytes32 _s) public {
        require(ecrecover(keccak256(_nonce, _nonceMax, _server), _v, _r, _s) == _client);
        require(now > clients[_client].endLottery);
        if (clients[_client].winningNumber == 0) {
            clients[_client].winningNumber = 42; // TODO get actual randomNumber, RANDAO ... between 0 and totalDeposit
        }
        
        uint probability = (_nonce * servers[_server].deposit) / _nonceMax; // TODO, use actual deposit at time lottery did start, consider Minime)

        if (_startDepositClaim + probability > clients[_client].winningNumber && clients[_client].winningNumber > _startDepositClaim && clients[_client].server.server == address(0x0)) {
            //_server.transfer(clients[_client].deposit);
            Claim memory claim;
            claim.server = _server;
            claim.startDepositClaim = _startDepositClaim;
            clients[_client].server = claim;
        }
    }
    
   
    function convictClaim(address _client) {
        uint claimedStartDeposit = clients[_client].server.startDepositClaim;
        address claimedAddress = clients[_client].server.server;
        uint claimedIndex = servers[claimedAddress].index;

        uint realStartDeposit;
        uint index;
        bool convicted;
        while (msg.gas > MINITERATIONGAS) {
            realStartDeposit += servers[serverAddresses[index]].deposit;
            if (realStartDeposit > claimedStartDeposit) || (realStartDeposit < claimedStartDeposit && index == claimedIndex) || index > claimedIndex )  {
                convcited = true;
                break;
            }
            index += 1;
        }
        if (convicted) {
            msg.sender.transfer(servers[claimedAddress].deposit);
            Claim memory claim;
            clients[_client] = claim;
            removerServer(claimedAddress);
        } 
        else {
            claimLoopIndex[msg.sender] = index;
        }        
    }

    function cleanUpClaimLoopIndex(address _client) {
        if (clients[_client].endLottery + 1 days < now) {
            claimLoopIndex[msg.sender] = 0;
        }
    }

    function payoutClaim(address _client) {
        address server = clients[_client].server.server;
        if (clients[_client].endLottery + 1 days < now && clients[_client].server.server != address(0x0)) {
            server.transfer(clients[_client].deposit);
        }
        else {
            _client.transfer(clients[_client].deposit);
        }
        Claim memory claim;
        clients[_client] = claim;
    }
}
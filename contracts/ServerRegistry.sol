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

        // unregister state
        uint unregisterTime; // earliest timestamp in to to call unregister
        address unregisterCaller; // address of the caller requesting the unregister
    }
    
    mapping(address => Web3Server) servers;

    /// register a new Server with the sender as owner    
    function registerServer(string _url, uint _props) public payable {
        // make sure this this owner was not registered before.
        require (servers[msg.sender].url[0] == 0);
        
        // create new Webserver
        Web3Server memory m;
        m.url = _url;
        m.props = _props;
        m.deposit = msg.value;
        servers[msg.sender] = m;
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
        LogServerRemoved(servers[_owner].url, s_owner );
        Web3Server memory m;
        servers[_owner] = m:
    }
}
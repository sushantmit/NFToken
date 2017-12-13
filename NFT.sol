// Things that have not been implemented but may be done at a later date
// Cooldown time for minting of new tokens



pragma solidity ^0.4.11; 

// Defines and ownable property and the owner. Simplifies user permissions
contract Ownable {
	address public owner;

	//contract constructor
	function Ownable() {
		// set the creator of the contract (who sent this message call) as the owner of the contract
		owner = msg.sender; 
	}

	//must be called by the owner else throws an error
	modifier onlyOwner() {
		require (msg.sender == owner);
		_; // otherwise just continues with execution
	}

	// ownership can only be transfered by current owner
	function transferOwnership(address newOwner) external onlyOwner {
		
		//newOwner address must be valid
		if (newOwner != address(0)){
			owner = new owner;
		}
	}
}


//Interface for contract conforming to ERC-721 standard : Non-Fungible Tokens (NFTs)
contract ERC721 {
    // Required methods
    function totalSupply() public view returns (uint256 total);
    function balanceOf(address _owner) public view returns (uint256 balance);
    function ownerOf(uint256 _tokenId) external view returns (address owner);
    function approve(address _to, uint256 _tokenId) external;
    function transfer(address _to, uint256 _tokenId) external;
    function transferFrom(address _from, address _to, uint256 _tokenId) external;

    // Events
    event Transfer(address from, address to, uint256 tokenId);
    event Approval(address owner, address approved, uint256 tokenId);

    // Optional
    // function name() public view returns (string name);
    // function symbol() public view returns (string symbol);
    // function tokensOfOwner(address _owner) external view returns (uint256[] tokenIds);
    // function tokenMetadata(uint256 _tokenId, string _preferredTransport) public view returns (string infoUrl);

    // ERC-165 Compatibility (https://github.com/ethereum/EIPs/issues/165)
    function supportsInterface(bytes4 _interfaceID) external view returns (bool);
}


// This contract manages special access privileges 
contract NFTokenAccessControl {

	// This contract controls the Access Control for NFToken. Roles managed by this are :
	// CEO - Can assign roles to new people. Can also pause and unpause the contract to update it.
	// CFO - Can withdraw funds from the NFTokenCore contract and auction contracts
	// COO - Can release new MyTokens for auction and mint new NFTokens

	//Fired when contract is upgraded
	event ContractUpgrade(address newContract);

	address public ceoAddress;
	address public cooAddress;
	address public cfoAddress;

	// To keep track of contract pause state
	bool public paused = false;

	// CEO Access modifier
	modifier onlyCEO() {
        require(msg.sender == ceoAddress);
        _;
    }

    // CFO Access modifier
    modifier onlyCFO() {
        require(msg.sender == cfoAddress);
        _;
    }

    // COO Access modifier
    modifier onlyCOO() {
    	require(msg.sender == cooAddress);
    	_;
    }

    // CEO or CFO or COO Access modifier
    modifier onlyCLevel() {
        require(
            msg.sender == cooAddress ||
            msg.sender == ceoAddress ||
            msg.sender == cfoAddress
        );
        _;
    }

    // Assigns a new address to act as CEO. Can only be called by current CEO.
    function setCEO(address _newCEO) external onlyCEO {
        require(_newCEO != address(0));
		ceoAddress = _newCEO;
    }

    // Assigns a new address to act as CFO. Can only be called by current CEO.
    function setCFO(address _newCFO) external onlyCEO {
        require(_newCFO != address(0));
		cfoAddress = _newCFO;
    }

    // Assigns a new address to act as COO. Can only be called by current CEO.
    function setCOO(address _newCOO) external onlyCEO {
        require(_newCOO != address(0));
		cooAddress = _newCOO;
    }

    // Modifier to allow actions to be peformed only when contract is not paused.
    modifier whenNotPaused() {
        require(!paused);
        _;
    }

    // Modifier to allow actiosn to be performed only whne contract is paused.
    modifier whenPaused {
        require(paused);
        _;
    }

    // Called by any "C-level" role to pause the contract.
    function pause() external onlyCLevel whenNotPaused {
        paused = true;
    }

    // Can be called by CEO account only. Public so that it can be called from derived contracts
    function unpause() public onlyCEO whenPaused {
        // can't unpause if contract was upgraded
        paused = false;
    }

}


// This contract holds all the basic and necessary data structures and the base token functions
contract NFTokenBase is TokenAccessControl {

	// The New Minted event is fired whenever a new Token comes into existence
	event NewMinted(address owner, uint256 tokenId) // If Token has traits (liek genes) then it those must also be passed to the event

	// The Transfer event is fired when a token is transfered to someone else
	event Transfer(address from, address to, uint256 tokenId)

	struct NFToken {

		// add variables to represent all properties and identifiers of the unique token here

		// The timestamp from the block when this Token came into existence
		uint64 mintTime;

	}

	
	// An array containing the NFToken struct for all existing NFTokens.
	// The Id of each token is actually an index to this array 
	NFToken nftkns[];

	// A mapping from Token Id to the owner of the token
	// All tokens have some valid owner address. Even newly minted tokens have a non zero owner
	mapping (uint256 => address) public tokenIndexToOwner;

	// A mapping form owner address to the count of tokens that the address owns
	// Used in balanceOf()
	mapping (address => uint256) ownershipTokenCount;

	// A mapping from Token Id to an address that has been approved to call transferFrom()
	// Each NFToken can have only one such address at a time
	// A zero value means no approval is outstanding.
	mapping (uint256 => address) public tokenIndexToApproved;

	// The address of the ClockAuction contract that handles sales of NFTokens.
	// This same contract handles both peer to peer sale and the sale of newly minted NFTokens
	SaleClockAuction public saleAuction;

	// Assigns the ownership of a specific NFToken to an address
	function _transfer(address _from, address _to, uint256 _tokenId) internal {

		// incremeting the ownership count of the address receiving the token
		ownershipTokenCount[_to]++ ;
		// transfer ownership of the token
		tokenIndexToOwner[_tokenId] = _to;
		// _from is 0x0 for new tokens, but that address cannot be accounted
		if(_from != address(0)) {
			ownershipTokenCount[_from]--;

			// clear any previously approved ownership exchange
			// Note - delete frees memory in case of a particular mapping, i.e a mapping of a particular key and has no effect if used on a whole mapping
			delete tokenIndexToApproved[_tokenId];

		}

		// Fire the Transfer Event
		Transfer(_from, _to, _tokenId)
	}

	// A internal function that creates a new NFToken and stores it.
	// This method doesn't do any checking and shoudl be called only when the input data is known to be valid.
	// Will generate both a NewMinted and a Transfer Events
	//also pass any other token related data required for token
	function createNFToken(address _owner) internal returns (uint) {

		// validate any other data passed (though not necessary). 
		NFToken memory _nft = NFToken({
			mintTime: uint64(now)
		});
		// pushing newly craeted tokens to the array that records all existing tokens
		// this also gives us the index that is the token Id
		uint256 newNFTokenID = nftkns.push(_nft) - 1;

		// binding the limit to the number of unique tokens possible to 2^32 (nearly 4.2 billion)
		// basically checking for overflow (though very unlikely to happen as the number is too large)
		require(newNFTokenID == uint256(uint32(newNFTokenID)));

		// Fire the NewMinted event
		NewMinted(_owner, newNFTokenID);

		// This will transfer the token the ownership of token and also fire the event
		_transfer(0, _owner, newNFTokenID);

		return newNFTokenID;

	}

}




























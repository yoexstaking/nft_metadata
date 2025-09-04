// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IVault {
    function sendCommission(address to, uint256 amount) external;
}

contract YOEXNFT {
    string public name = "YoExNFT";
    string public symbol = "YOEXN";

    uint256 private _nextId = 1;
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    IERC20 public yoex;
    address public owner;
    IVault public vault;

    mapping(address => address) public sponsorOf;
    mapping(address => bool) public isRegistered;

    enum LockPlan { OPEN, THREE, SIX, TWELVE }

    struct NftData {
        string name_;
        string description_;
        string imageURL_;
        uint256 basePrice;
        LockPlan plan;
        uint64 lockEnd;
        address creator;
    }

    struct Listing {
        bool active;
        uint256 price;
    }

    mapping(uint256 => NftData) private _meta;
    mapping(uint256 => Listing) public listings;

    uint16 public constant COMM_THREE = 500;
    uint16 public constant COMM_SIX = 800;
    uint16 public constant COMM_TWELVE = 1000;
    uint16 public constant BPS_DENOMINATOR = 10000;

    struct Commission {
        address buyer;
        uint256 tokenId;
        uint256 amount;
        uint256 timestamp;
    }
    mapping(address => Commission[]) public directCommissions;
    mapping(address => uint256) public totalDirectCommission;

    struct Purchase {
        uint256 tokenId;
        uint256 price;
        uint256 timestamp;
        address seller;
    }
    mapping(address => Purchase[]) public buyHistory;

    struct Sale {
        uint256 tokenId;
        uint256 price;
        uint256 timestamp;
        address buyer;
        bool completed;
    }
    mapping(address => Sale[]) public sellHistory;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event Registered(address indexed user, address indexed sponsor);
    event Minted(uint256 indexed tokenId, address indexed to, string name_, uint256 price);
    event Listed(uint256 indexed tokenId, uint256 price);
    event Purchased(uint256 indexed tokenId, address indexed buyer, address indexed seller, uint256 price, uint256 commission);

    constructor(address _yoex, address firstUser, address _vault) {
        yoex = IERC20(_yoex);
        owner = firstUser;
        isRegistered[firstUser] = true;
        vault = IVault(_vault);
    }

    function toString(uint256 value) public pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == 0x80ac58cd || interfaceId == 0x5b5e139f;
    }

    function balanceOf(address addr) external view returns (uint256) {
        require(addr != address(0));
        return _balances[addr];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = _owners[tokenId];
        require(tokenOwner != address(0));
        return tokenOwner;
    }

    function approve(address to, uint256 tokenId) external {
        address tokenOwner = ownerOf(tokenId);
        require(to != tokenOwner);
        require(msg.sender == tokenOwner || _operatorApprovals[tokenOwner][msg.sender]);
        _tokenApprovals[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        require(_owners[tokenId] != address(0));
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        require(operator != msg.sender);
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address tokenOwner, address operator) external view returns (bool) {
        return _operatorApprovals[tokenOwner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        require(_isApprovedOrOwner(msg.sender, tokenId));
        _transfer(from, to, tokenId);
    }


    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(_owners[tokenId] != address(0));
        return string(abi.encodePacked(
            "https://raw.githubusercontent.com/yoexstaking/nft_metadata/refs/heads/main/metadata/",
            toString(tokenId),
            ".json"
        ));
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address tokenOwner = ownerOf(tokenId);
        return (spender == tokenOwner || 
                _operatorApprovals[tokenOwner][spender] || 
                _tokenApprovals[tokenId] == spender);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from);
        require(to != address(0));
        delete _tokenApprovals[tokenId];
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0));
        require(_owners[tokenId] == address(0));
        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
    }

    function register(address sponsorWallet) external {
        require(!isRegistered[msg.sender]);
        require(sponsorWallet != msg.sender);
        if (sponsorWallet != address(0)) {
            require(isRegistered[sponsorWallet]);
        }
        sponsorOf[msg.sender] = sponsorWallet;
        isRegistered[msg.sender] = true;
        emit Registered(msg.sender, sponsorWallet);
    }

    function createNFT(
        string calldata nft_name,
        string calldata nft_description,
        string calldata nft_image_url,
        uint256 nft_price
    ) external returns (uint256 tokenId) {
        tokenId = _nextId++;
        _mint(msg.sender, tokenId);
        _meta[tokenId] = NftData(
            nft_name,
            nft_description,
            nft_image_url,
            nft_price,
            LockPlan.OPEN,
            0,
            msg.sender
        );
        emit Minted(tokenId, msg.sender, nft_name, nft_price);
    }

    function listNFT(uint256 tokenId, uint256 price) external {
        require(ownerOf(tokenId) == msg.sender);
        require(block.timestamp >= _meta[tokenId].lockEnd);
        listings[tokenId] = Listing(true, price);
        sellHistory[msg.sender].push(Sale(tokenId, price, block.timestamp, address(0), false));
        emit Listed(tokenId, price);
    }

    function buyNFT(uint256 tokenId, uint8 lockPlanChoice) external {
        Listing memory lst = listings[tokenId];
        require(lst.active);
        require(lockPlanChoice <= 3);

        address seller = ownerOf(tokenId);
        require(seller != msg.sender);

        _meta[tokenId].plan = LockPlan(lockPlanChoice);
        if (lockPlanChoice > 0) {
            _meta[tokenId].lockEnd = uint64(block.timestamp + _lockDuration(lockPlanChoice));
        }

        listings[tokenId].active = false;

        uint256 commission = 0;
        address sponsor = sponsorOf[seller];
        uint16 commBps = _commissionBps(LockPlan(lockPlanChoice));
        
        if (commBps > 0 && sponsor != address(0)) {
            commission = (lst.price * commBps) / BPS_DENOMINATOR;
            vault.sendCommission(sponsor, commission);
            directCommissions[sponsor].push(Commission(msg.sender, tokenId, commission, block.timestamp));
            totalDirectCommission[sponsor] += commission;
        }

        require(yoex.transferFrom(msg.sender, seller, lst.price));
        _transfer(seller, msg.sender, tokenId);

        buyHistory[msg.sender].push(Purchase(tokenId, lst.price, block.timestamp, seller));

        Sale[] storage sHist = sellHistory[seller];
        for (uint i = 0; i < sHist.length; i++) {
            if (sHist[i].tokenId == tokenId && !sHist[i].completed) {
                sHist[i].completed = true;
                sHist[i].buyer = msg.sender;
                break;
            }
        }

        emit Purchased(tokenId, msg.sender, seller, lst.price, commission);
    }

    function _commissionBps(LockPlan plan) internal pure returns (uint16) {
        if (plan == LockPlan.THREE) return COMM_THREE;    // 5%
        if (plan == LockPlan.SIX) return COMM_SIX;        // 8%
        if (plan == LockPlan.TWELVE) return COMM_TWELVE;  // 10%
        return 0; // OPEN - no commission
    }

    function _lockDuration(uint8 planChoice) internal pure returns (uint256) {
        if (planChoice == 1) return 90 days;   // 3 months
        if (planChoice == 2) return 180 days;  // 6 months
        if (planChoice == 3) return 365 days;  // 12 months
        return 0;
    }

    function totalSupply() external view returns (uint256) {
        return _nextId - 1;
    }

    function getNFT(uint256 tokenId) external view returns (NftData memory) {
        require(_owners[tokenId] != address(0));
        return _meta[tokenId];
    }

    function isTokenLocked(uint256 tokenId) external view returns (bool) {
        require(_owners[tokenId] != address(0));
        return block.timestamp < _meta[tokenId].lockEnd;
    }

    function getTokenLockInfo(uint256 tokenId) external view returns (
        bool isLocked,
        uint64 lockEnd,
        LockPlan plan
    ) {
        require(_owners[tokenId] != address(0));
        NftData memory nft = _meta[tokenId];
        isLocked = block.timestamp < nft.lockEnd;
        lockEnd = nft.lockEnd;
        plan = nft.plan;
    }

    function tokensOfOwner(address ownerAddr) external view returns (uint256[] memory) {
        uint256 tokenCount = _balances[ownerAddr];
        uint256[] memory tokens = new uint256[](tokenCount);
        uint256 index = 0;
        
        for (uint256 i = 1; i < _nextId && index < tokenCount; i++) {
            if (_owners[i] == ownerAddr) {
                tokens[index] = i;
                index++;
            }
        }
        return tokens;
    }

    function getActiveListings() external view returns (uint256[] memory tokenIds, uint256[] memory prices) {
        uint256 activeCount = 0;
        
        // Count active listings
        for (uint256 i = 1; i < _nextId; i++) {
            if (listings[i].active) {
                activeCount++;
            }
        }
        
        tokenIds = new uint256[](activeCount);
        prices = new uint256[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 1; i < _nextId; i++) {
            if (listings[i].active) {
                tokenIds[index] = i;
                prices[index] = listings[i].price;
                index++;
            }
        }
    }

    function getUserCommissionStats(address user) external view returns (
        uint256 totalCommissions,
        uint256 totalTransactions
    ) {
        totalCommissions = totalDirectCommission[user];
        totalTransactions = directCommissions[user].length;
    }

    // Admin functions
    function updateVault(address newVault) external {
        require(msg.sender == owner);
        vault = IVault(newVault);
    }

    function updateNFTPrice(uint256 tokenId, uint256 newPrice) external {
        require(msg.sender == owner);
        require(_owners[tokenId] != address(0));
        _meta[tokenId].basePrice = newPrice;
    }

    function updateNFTName(uint256 tokenId, string calldata newName) external {
        require(msg.sender == owner);
        require(_owners[tokenId] != address(0));
        _meta[tokenId].name_ = newName;
    }

    function updateNFTDescription(uint256 tokenId, string calldata newDesc) external {
        require(msg.sender == owner);
        require(_owners[tokenId] != address(0));
        _meta[tokenId].description_ = newDesc;
    }

    function updateNFTImage(uint256 tokenId, string calldata newImage) external {
        require(msg.sender == owner);
        require(_owners[tokenId] != address(0));
        _meta[tokenId].imageURL_ = newImage;
    }


    function unlistNFT(uint256 tokenId) external {
        require(msg.sender == owner || ownerOf(tokenId) == msg.sender);
        listings[tokenId].active = false;
    }
}

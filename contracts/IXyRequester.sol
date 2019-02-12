pragma solidity >=0.5.0 <0.6.0;

interface IXyRequester {
    struct IPFSRequest {
        uint requestId;
        uint weiPayment;
        uint xyoPayment;
        uint createdAt;
        uint responseAt;
        address payable beneficiary;
        address payable asker;
    }

    function submitResponse(uint question, uint8 requestType, bytes calldata response) external;
}
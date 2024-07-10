# PetApi

All URIs are relative to *http://petstore.swagger.io/v2*

Method | HTTP request | Description
------------- | ------------- | -------------
[**find_pets_by_status**](PetApi.md#find_pets_by_status) | **GET** /pet/findByStatus | Finds Pets by status


# **find_pets_by_status**
> find_pets_by_status(_api::PetApi, status::FindPetsByStatusStatusParameter; _mediaType=nothing) -> FindPetsByStatus200Response, OpenAPI.Clients.ApiResponse <br/>
> find_pets_by_status(_api::PetApi, response_stream::Channel, status::FindPetsByStatusStatusParameter; _mediaType=nothing) -> Channel{ FindPetsByStatus200Response }, OpenAPI.Clients.ApiResponse

Finds Pets by status

Multiple status values can be provided with comma separated strings

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **PetApi** | API context | 
**status** | [**FindPetsByStatusStatusParameter**](.md)| Status values that need to be considered for filter | [default to nothing]

### Return type

[**FindPetsByStatus200Response**](FindPetsByStatus200Response.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)

